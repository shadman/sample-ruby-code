# USAGE:
#
# phone_number = '300123456X'
# message = 'your message text here'
# user_id = 12345
# checkin_id = 1
# sms_service = SendSMSService.new(phone_number, message, user_id checkin_id)
# service_response = sms_service.perform
#
# # call the service without checkin_id. checkin_id is only used for logging
# phone_number = '300123456X'
# message = 'your message text here'
# user_id = 12345
# sms_service = SendSMSService.new(phone_number, message, user_id)
# service_response = sms_service.perform
#
# # get and set object parameters after initialization and before perform
# sms_service = SendSMSService.new(phone_number, message)
# sms_service.message = 'updated message'
# sms_service.checkin_id = 123
# service_response = sms_service.perform

class SendSMSService
  attr_accessor :phone_number, :message, :user_id, :checkin_id

  def initialize(phone_number, message, user_id, checkin_id = nil)
    @phone_number = phone_number
    @message = message
    @user_id = user_id
    @from_number = APP_CONFIG['from_sms_phone']
    @checkin_id = checkin_id
  end

  def perform
    setup_client
    result = send_sms_wih_twillio
    create_log(result)

    ServiceResult.new nil, result[:success], result[:err_message]
  end

  private

  def setup_client
    account_sid = APP_CONFIG['twilio_account_sid']
    auth_token = APP_CONFIG['twilio_auth_token']
    @client = Twilio::REST::Client.new account_sid, auth_token
  end

  def send_sms_wih_twillio
    success = true
    err_message = nil

    begin
      @client.messages.create(
        from: @from_number,
        to: "+#{APP_CONFIG['sms_country_code']}#{@phone_number}",
        body: "#{APP_CONFIG['mesg_env_prefix']}#{@message}")

    rescue Twilio::REST::RequestError => e
      success = false
      err_message = e.message
    end

    { success: success, err_message: err_message }
  end

  def create_log(result)
    sms_log = LoggedSms.new(
      user_id: @user_id, checkin_id: @checkin_id, is_success: result[:success], from_number: @from_number,
      to_number: @phone_number, message: @message, error_message: result[:err_message])

    sms_log.save!
  end
end
