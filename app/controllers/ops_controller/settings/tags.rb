module OpsController::Settings::Tags
  extend ActiveSupport::Concern

  # AJAX routine for user selected
  def category_select
    if params[:id] == "new"
      javascript_redirect(:action => 'category_new') # redirect to new
    else
      javascript_redirect(:action => 'category_edit', :id => params[:id], :field => params[:field]) # redirect to edit
    end
  end

  # AJAX driven routine to delete a category
  def category_delete
    assert_privileges("region_edit")

    category = Classification.find(params[:id])
    c_name = category.name
    audit = {:event        => "category_record_delete",
             :message      => "[#{c_name}] Record deleted",
             :target_id    => category.id,
             :target_class => "Classification",
             :userid       => session[:userid]}
    if category.destroy
      AuditEvent.success(audit)
      add_flash(_("Category \"%{name}\": Delete successful") % {:name => c_name})
      category_get_all
      render :update do |page|
        page << javascript_prologue
        page.replace("flash_msg_div", :partial => "layouts/flash_msg")
        page << "miqScrollTop();" if @flash_array.present?
        page.replace_html('settings_co_categories', :partial => 'settings_co_categories_tab')
      end
    else
      category.errors.each { |error| add_flash("#{error.attribute.to_s.capitalize} #{error.message}", :error) }
      javascript_flash
    end
  end

  def category_edit
    assert_privileges("region_edit")

    case params[:button]
    when "cancel"
      @category = session[:edit][:category] if session[:edit] && session[:edit][:category]
      if !@category || @category.id.blank?
        add_flash(_("Add of new Category was cancelled by the user"))
      else
        add_flash(_("Edit of Category \"%{name}\" was cancelled by the user") % {:name => @category.name})
      end
      get_node_info(x_node)
      @category = @edit = session[:edit] = nil # clean out the saved info
      replace_right_cell(:nodetype => @nodetype)
    when "save", "add"
      id = params[:id] || "new"
      return unless load_edit("category_edit__#{id}", "replace_cell__explorer")

      @ldap_group = @edit[:ldap_group] if @edit && @edit[:ldap_group]
      @category = @edit[:category] if @edit && @edit[:category]
      if @edit[:new][:name].blank?
        add_flash(_("Name is required"), :error)
      end
      if @edit[:new][:description].blank?
        add_flash(_("Description is required"), :error)
      end
      if @edit[:new][:example_text].blank?
        add_flash(_("Long Description is required"), :error)
      end
      unless @flash_array.nil?
        javascript_flash
        return
      end
      if params[:button] == "add"
        begin
          Classification.create_category!(:name         => @edit[:new][:name],
                                          :description  => @edit[:new][:description],
                                          :single_value => @edit[:new][:single_value],
                                          :perf_by_tag  => @edit[:new][:perf_by_tag],
                                          :example_text => @edit[:new][:example_text],
                                          :show         => @edit[:new][:show])
        rescue => bang
          add_flash(_("Error during 'add': %{message}") % {:message => bang.message}, :error)
          javascript_flash
        else
          @category = Classification.find_by(:description => @edit[:new][:description])
          AuditEvent.success(build_created_audit(@category, @edit))
          add_flash(_("Category \"%{name}\" was added") % {:name => @category.name})
          get_node_info(x_node)
          @category = @edit = session[:edit] = nil # clean out the saved info
          replace_right_cell(:nodetype => "root")
        end
      else
        update_category = Classification.find(@category.id)
        category_set_record_vars(update_category)
        begin
          update_category.save!
        rescue
          update_category.errors.each do |error|
            add_flash("#{error.attribute.to_s.capitalize} #{error.message}", :error)
          end
          @in_a_form = true
          session[:changed] = @changed
          @changed = true
          javascript_flash
        else
          add_flash(_("Category \"%{name}\" was saved") % {:name => update_category.name})
          AuditEvent.success(build_saved_audit(update_category, params[:button] == "add"))
          session[:edit] = nil # clean out the saved info
          get_node_info(x_node)
          @category = @edit = session[:edit] = nil # clean out the saved info
          replace_right_cell(:nodetype => "root")
        end
      end
    when "reset", nil # Reset or first time in
      if params[:id]
        @category = Classification.find(params[:id])
        category_set_form_vars
      else
        category_set_new_form_vars
      end
      @in_a_form = true
      session[:changed] = false
      if params[:button] == "reset"
        add_flash(_("All changes have been reset"), :warning)
      end
      replace_right_cell(:nodetype => "ce")
    end
  end

  # AJAX driven routine to check for changes in ANY field on the user form
  def category_field_changed
    assert_privileges("region_edit")

    return unless load_edit("category_edit__#{params[:id]}", "replace_cell__explorer")

    category_get_form_vars
    @changed = (@edit[:new] != @edit[:current])
    render :update do |page|
      page << javascript_prologue
      if @refresh_div
        page.replace(@refresh_div, :partial => @refresh_partial,
                                   :locals  => {:type => "classifications", :action_url => 'category_field_changed'})
      end
      page << javascript_for_miq_button_visibility_changed(@changed)
    end
  end

  # A new classificiation category was selected
  def ce_new_cat
    assert_privileges("region_edit")

    ce_get_form_vars
    if params[:classification_name]
      @cat = Classification.lookup_by_name(params["classification_name"])
      ce_build_screen # Build the Classification Edit screen
      render :update do |page|
        page << javascript_prologue
        page.replace(:tab_div, :partial => "settings_co_tags_tab")
      end
    end
  end

  # AJAX driven routine to select a classification entry
  def ce_select
    assert_privileges("region_edit")

    ce_get_form_vars
    if params[:id] == "new"
      render :update do |page|
        page << javascript_prologue
        page.replace("flash_msg_div", :partial => "layouts/flash_msg")
        page << "miqScrollTop();" if @flash_array.present?
        page.replace("classification_entries_div", :partial => "classification_entries", :locals => {:entry => "new", :edit => true})
        page << javascript_focus('entry_name')
        page << "$('#entry_name').select();"
      end
      session[:entry] = "new"
    else
      entry = Classification.find(params[:id])
      render :update do |page|
        page << javascript_prologue
        page.replace("flash_msg_div", :partial => "layouts/flash_msg")
        page << "miqScrollTop();" if @flash_array.present?
        page.replace("classification_entries_div", :partial => "classification_entries", :locals => {:entry => entry, :edit => true})
        page << javascript_focus("entry_#{j_str(params[:field])}")
        page << "$('#entry_#{j_str(params[:field])}').select();"
      end
      session[:entry] = entry
    end
  end

  # AJAX driven routine to add/update a classification entry
  def ce_accept
    assert_privileges("region_edit")

    ce_get_form_vars
    if session[:entry] == "new"
      entry = @cat.entries.create(:name        => params["entry"]["name"],
                                  :description => params["entry"]["description"])
    else
      entry = @cat.entries.find(session[:entry].id)
      if entry.name == params["entry"]["name"] && entry.description == params["entry"]["description"]
        no_changes = true
      else
        entry.name        = params["entry"]["name"]
        entry.description = params["entry"]["description"]
        entry.save
      end
    end
    unless entry.errors.empty?
      entry.errors.each { |error| add_flash("#{error.attribute.to_s.capitalize} #{error.message}", :error) }
      javascript_flash(:focus => 'entry_name')
      return
    end
    if session[:entry] == "new"
      AuditEvent.success(ce_created_audit(entry))
    else
      AuditEvent.success(ce_saved_audit(entry)) unless no_changes
    end
    ce_build_screen # Build the Classification Edit screen
    render :update do |page|
      page << javascript_prologue
      page.replace(:tab_div, :partial => "settings_co_tags_tab")
      unless no_changes
        page << jquery_pulsate_element("#{entry.id}_tr")
      end
    end
  end

  # AJAX driven routine to delete a classification entry
  def ce_delete
    assert_privileges("region_edit")

    ce_get_form_vars
    entry = @cat.entries.find(params[:id])
    audit = {:event        => "classification_entry_delete",
             :message      => _("Category %{description} [%{name}] record deleted") % {:description => @cat.description,
                                                                                       :name        => entry.name},
             :target_id    => entry.id,
             :target_class => "Classification",
             :userid       => session[:userid]}
    if entry.destroy
      AuditEvent.success(audit)
      ce_build_screen # Build the Classification Edit screen
      render :update do |page|
        page << javascript_prologue
        page.replace(:tab_div, :partial => "settings_co_tags_tab")
      end
    else
      entry.errors.each { |error| add_flash("#{error.attribute.to_s.capitalize} #{error.message}", :error) }
      javascript_flash(:focus => 'entry_name')
    end
  end

  def ce_get_form_vars
    @edit = session[:edit]
    @cats = session[:config_cats]
    @cat = Classification.lookup_by_name(session[:config_cat])
    nil
  end

  private

  # Build the classification edit screen from the category record in @cat
  def ce_build_screen
    session[:config_cats] = @cats
    session[:config_cat] = @cat.name
    session[:entry] = nil
  end

  # Build the audit object when a record is created, including all of the new fields
  def ce_created_audit(entry)
    msg = _("Category %{description} [%{name}] record created (") % {:description => @cat.description,
                                                                     :name        => entry.name}
    event = "classification_entry_add"
    i = 0
    params["entry"].each do |k, _v|
      msg += ", " if i.positive?
      i += 1
      msg = msg + k.to_s + ":[" + params["entry"][k].to_s + "]"
    end
    msg += ")"
    {:event => event, :target_id => entry.id, :target_class => entry.class.base_class.name, :userid => session[:userid], :message => msg}
  end

  # Build the audit object when a record is saved, including all of the changed fields
  def ce_saved_audit(entry)
    msg = _("Category %{description} [%{name}] record updated (") % {:description => @cat.description,
                                                                     :name        => entry.name}
    event = "classification_entry_update"
    i = 0
    if entry.name != session[:entry].name
      i += 1
      msg += _("name:[%{session}] to [%{name}]") % {:session => session[:entry].name, :name => entry.name}
    end
    if entry.description != session[:entry].description
      msg += ", " if i.positive?
      msg += _("description:[%{session}] to [%{name}]") % {:session => session[:entry].description,
                                                           :name    => entry.description}
    end
    msg += ")"
    {:event => event, :target_id => entry.id, :target_class => entry.class.base_class.name, :userid => session[:userid], :message => msg}
  end

  # Get variables from category edit form
  def category_get_form_vars
    @category = @edit[:category]
    copy_params_if_present(@edit[:new], params, %i[name description example_text])
    @edit[:new][:show] = (params[:show] == 'true') if params[:show]
    @edit[:new][:perf_by_tag] = (params[:perf_by_tag] == "true") if params[:perf_by_tag]
    @edit[:new][:single_value] = (params[:single_value] == "true") if params[:single_value]
  end

  def category_get_all
    cats = Classification.categories.sort_by(&:name) # Get the categories, sort by name
    @categories = []                                 # Classifications array for first chooser
    cats.each do |c|
      next if c.read_only? # Show the non-read_only categories

      cat = {}
      cat[:id] = c.id
      cat[:description] = c.description
      cat[:name] = c.name
      cat[:show] = c.show
      cat[:single_value] = c.single_value
      cat[:perf_by_tag] = c.perf_by_tag
      cat[:default] = c.default
      @categories.push(cat)
    end
  end

  # Set form variables for category add/edit
  def category_set_form_vars
    @edit = {}
    @edit[:category] = @category
    @edit[:new] = {}
    @edit[:current] = {}
    @edit[:key] = "category_edit__#{@category.id || "new"}"
    @edit[:new][:name] = @category.name
    @edit[:new][:description] = @category.description
    @edit[:new][:show] = @category.show
    @edit[:new][:perf_by_tag] = @category.perf_by_tag
    @edit[:new][:default] = @category.default
    @edit[:new][:single_value] = @category.single_value
    @edit[:new][:example_text] = @category.example_text
    @edit[:current] = copy_hash(@edit[:new])
    session[:edit] = @edit
  end

  # Set form variables for category add/edit
  def category_set_new_form_vars
    @edit = {}
    @edit[:user] = @user
    @edit[:new] = {}
    @edit[:current] = {}
    @edit[:key] = "category_edit__new"
    @edit[:new][:name] = nil
    @edit[:new][:description] = nil
    @edit[:new][:show] = true
    @edit[:new][:perf_by_tag] = false
    @edit[:new][:default] = false
    @edit[:new][:single_value] = true
    @edit[:new][:example_text] = nil
    @edit[:current] = copy_hash(@edit[:new])
    session[:edit] = @edit
  end

  # Set category record variables to new values
  def category_set_record_vars(category)
    category.description = @edit[:new][:description]
    category.example_text = @edit[:new][:example_text]
    category.show = @edit[:new][:show]
    category.perf_by_tag = @edit[:new][:perf_by_tag]
  end
end
