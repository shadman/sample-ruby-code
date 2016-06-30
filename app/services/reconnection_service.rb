class ReconnectionService
  attr_accessor :user, :type, :current_location

  def initialize(user, type, current_location)
    @user = user
    @type = type
    @current_location = current_location
  end

  def perform
    user_reconnection(@user, @type, @current_location)
  end

  private

  def user_reconnection(user, type, current_location)
    case_manager_name = I18n.t('case_manager')
    enrollee_name = "#{user.first_name} #{user.last_name}"
    user_last_location = UserLastLocation.user_last_location(user.id)
    fake_location = user_last_location.nil? ? 0 : user_last_location.is_fake_location
    last_bg_location_at = user.last_bg_location_at
    is_disconnected = user.is_disconnected
    case_manager = user.admin_user
    current_timestamp = Helper::DateTimeHelper.current_datetime
    user_zone = user.facility.time_zone
    date_time = Helper::DateTimeHelper.utc_to_facility_datetime_in_AM_PM_format(current_timestamp, user_zone)
    user_attributes = generate_user_attributes(user, current_timestamp)
    user.update_using_attributes(user_attributes)

    if current_timestamp.present? && last_bg_location_at.present? && is_disconnected &&
       (current_timestamp - 30.minutes) > last_bg_location_at

      disconnection_time = Helper::DateTimeHelper.calculate_time_difference(current_timestamp,
                                                                            last_bg_location_at)
      current_location = generate_location(current_location, type)
      if fake_location.to_i > 0
        font_id = APP_CONFIG['red_font_id']
        note = I18n.t('note')
        current_location = "#{current_location} *"
      else
        note = font_id = ''
      end
      params = {
        case_manager_name: case_manager_name,
        enrollee_name: enrollee_name,
        disconnection_time: disconnection_time,
        current_location: current_location,
        date_time: date_time,
        font_id: font_id,
        note: note
      }
      send_email(case_manager, params)
      Helper::SMSHelper.sms_alert_to_case_manager(case_manager.id, APP_CONFIG['sms_admin_alert_types'][1],
                                                  params)
    end
  end

  def send_email(case_manager, params_email)
    recipient_email = ''
    email_subject = I18n.t('email_subject')
    email_template = 'enrollee_connected_alert.html.erb'
    email_service = SendEmailService.new(email_template, recipient_email, email_subject, params_email)

    email_preferences = AdminUserAlerts.get_admin_alerts_preferences(case_manager.id)
    if email_preferences.present? && email_preferences.email_connect_disconnect_alert.present?

      other_email = AdminUserAlerts.get_other_alerts_email_array(case_manager.id)

      # send primary email alerts
      if email_preferences.primary_email_alerts.present?
        email_service.recipient_email = case_manager.email
        service_response = email_service.perform
      end

      # send secondary email alerts
      if email_preferences.secondary_email_alerts.present? && other_email.present?
        other_email.each do |email|
          email_service.recipient_email = email
          service_response = email_service.perform
        end
      end
    end
  end

  def generate_location(current_location, type)
    # logger added as it is needed in the requirements
    Rails.logger.info "Location Type: '#{type}'"
    return current_location.location if current_location.location.present?
    "#{current_location.latitude}, #{current_location.longitude}"
  end

  def generate_user_attributes(user, current_timestamp)
    if user.last_bg_location_at.nil? || current_timestamp > user.last_bg_location_at
      return {
        last_bg_location_at: current_timestamp,
        last_connection_checked_at: current_timestamp,
        is_disconnected: false,
        is_disconnected_pn: false
      }
    end
    { is_disconnected: false, is_disconnected_pn: false }
  end
end
