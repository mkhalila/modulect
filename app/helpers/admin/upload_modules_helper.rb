module Admin::UploadModulesHelper

  include Admin::MultiItemFieldHelper

  def upload_uni_module(new_record, uploader)
    creations = 0
    updates = 0

    csv_module = find_module_by_code(new_record['code'])

    # If departments cell is left empty in csv then turn it into empty string
    # So that nothing is called on nil
    new_record_departments = new_record['departments']
    if new_record_departments.nil?
      new_record_departments = ''
    end

    if invalid_module_create?(csv_module, new_record_departments, uploader)
      flash[:error] = "Failed to create module #{new_record['code']}: Module not linked to your department"
    elsif invalid_module_update?(csv_module, new_record_departments, uploader)
      flash[:error] = "Failed to update module #{new_record['code']}: Module not linked to your department"
    else
      # All validation checks passed
      new_record['semester'] = convert_semester_to_enum(new_record['semester'])

      if csv_module.nil?
        csv_module = try_to_create_module(new_record, uploader)
        creations += 1
      else
        csv_module = try_to_update_module(csv_module, new_record, uploader)
        updates += 1
      end

      if should_save?(csv_module)
        csv_module.save
      else
        display_errors csv_module
      end
    end

    return creations, updates
  end

  private
  def invalid_module_create?(csv_module, new_record_departments, uploader)
    # Prevent creating modules that don't belong to their department
    dept_admin_invalid_request = is_not_super_admin?(uploader) && !new_record_departments.include?(uploader.department.name)
    !being_updated?(csv_module) && dept_admin_invalid_request
  end

  def invalid_module_update?(csv_module, new_record_departments, uploader)
    # Prevent updating modules not in their department and prevent un-linking their own dept from module
    is_not_super_admin?(uploader) && being_updated?(csv_module) && (!csv_module.departments.include?(uploader.department) || !new_record_departments.include?(uploader.department.name))
  end

  def try_to_create_module(new_record, uploader)
    new_module = UniModule.new(new_record.except(
        'departments',
        'prerequisite_modules',
        'career_tags',
        'interest_tags'))

    update_module_departments(new_module, new_record, uploader)
    update_prerequisite_modules(new_module, new_record)
    update_career_tags(new_module, new_record)
    update_interest_tags(new_module, new_record)

    new_module
  end

  def try_to_update_module(updated_module, new_record, uploader)
    updated_module.assign_attributes(new_record.except(
        'departments',
        'prerequisite_modules',
        'career_tags',
        'interest_tags'))

    update_module_departments(updated_module, new_record, uploader)
    update_prerequisite_modules(updated_module, new_record)
    update_career_tags(updated_module, new_record)
    update_interest_tags(updated_module, new_record)

    updated_module
  end

  def update_module_departments(uni_module, new_record, uploader)
    uni_module.departments.clear
    uploaded_department_names = split_multi_association_field(new_record['departments'])
    unless uploaded_department_names.blank?
      uploaded_department_names.each do |dept_name|
        chosen_dept = find_department_by_name(dept_name)
        uni_module.departments << chosen_dept
      end
    end
  end

  def update_prerequisite_modules(uni_module, new_record)
    uni_module.uni_modules.clear
    prerequisite_codes = split_multi_association_field(new_record['prerequisite_modules'])
    unless prerequisite_codes.blank?
      unless prerequisite_codes.include? uni_module.name
        prerequisite_codes.each do |prerequisite_code|
          chosen_mod = find_module_by_code(prerequisite_code)
          if !chosen_mod.blank?
            uni_module.uni_modules << chosen_mod
          else
            uni_module.errors[:base] << "Could not find module by code: #{prerequisite_code}"
          end
        end
      end
    end
  end

  def update_career_tags(uni_module, new_record)
    uni_module.tags.clear
    uploaded_career_tags = split_multi_association_field(new_record['career_tags'])
    unless uploaded_career_tags.blank?
      uploaded_career_tags.each do |tag_name|
        chosen_tag = find_tag_by_name(tag_name)
        if chosen_tag.present?
          uni_module.tags << chosen_tag
        else
          new_tag = Tag.new(name: tag_name, type: 'CareerTag')
          uni_module.tags << new_tag
        end
      end
    end
  end

  def update_interest_tags(uni_module, new_record)
    uni_module.interest_tags.clear
    uploaded_interest_tags = split_multi_association_field(new_record['interest_tags'])
    unless uploaded_interest_tags.blank?
      uploaded_interest_tags.each do |tag_name|
        chosen_tag = find_tag_by_name(tag_name)
        if chosen_tag.present?
          uni_module.tags << chosen_tag
        else
          new_tag = Tag.new(name: tag_name, type: 'InterestTag')
          uni_module.tags << new_tag
        end
      end
    end
  end

  def should_save?(csv_module)
    !invalid_module?(csv_module)
  end

# Calling csv_module#valid? will override the already existent errors.
# Make sure that valid_base_attributes? is called last so no errors are overridden.
  def invalid_module?(csv_module)
    !csv_module.errors.empty? || !valid_associations?(csv_module) || !valid_base_attributes?(csv_module)
  end

  def valid_base_attributes?(record)
    record.valid?
  end

  def valid_associations?(csv_module)
    valid_module = false
    if csv_module.tags.empty?
      csv_module.errors[:base] << "At least a Tag must be given"
    elsif csv_module.departments.empty?
      csv_module.errors[:base] << "At least a Department must be given"
    else
      valid_module = true
    end

    valid_module
  end

  def display_errors(csv_module)
    update_error = "Update Failed: "
    csv_module.errors.full_messages.each do |error|
      update_error += error + '; '
    end
    flash[:error] = update_error
  end

  def find_department_by_name(name)
    Department.find_by_name(name)
  end

  def find_module_by_code(code)
    UniModule.find_by_code(code)
  end

  def find_tag_by_name(name)
    Tag.find_by_name(name)
  end

  def convert_semester_to_enum(semester)
    case semester
      when '1 or 2'
        0
      when '1'
        1
      when '2'
        2
      else
        3
    end
  end

  def being_updated?(the_module)
    !the_module.nil?
  end

  def is_not_super_admin?(uploader)
    uploader.user_level != 'super_admin_access'
  end
end
