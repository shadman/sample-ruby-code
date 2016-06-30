class RequiredLocation < ActiveRecord::Base
  def self.request_status(user_id, cm_id)
    # cm_id is for the future usage when more than one case manager
    # can send request to single enrollee.
    to_date = Time.now.utc
    from_date = (to_date - APP_CONFIG['current_location_request_expire_time'].minute)
    request_location = RequiredLocation.where(user_id: user_id, is_required: true,
                                              created_at: from_date..to_date)
    request_location.present?
  end

  def self.request(user_id, cm_id)
    RequiredLocation.where(user_id: user_id, case_manager_id: cm_id)
  end

  def self.create_request(user_id, cm_id)
    request = RequiredLocation.new(user_id: user_id, case_manager_id: cm_id, is_required: true)
    request.save
  end

  def self.remove_request(user_id, cm_id)
    request = RequiredLocation.where(user_id: user_id, case_manager_id: cm_id)
    RequiredLocation.destroy(request.first.id) if request.present?
  end
end
