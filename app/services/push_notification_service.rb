# USAGE:
#
# - Sends push notifications to single or multiple users.
# - The value of notification type parameter must be one of these three:
# PushNotificationService::GEOFENCE, PushNotificationService::CHECKIN, PushNotificationService::LOCATION
# - For sending notification to single user `user_ids` parameter should be a single value and
# for send notification to multiple users `user_ids` should an array of user ids
# - By default all notifications show alert and play sound on device.
# - To send notifications that neither show alert nor play sound (silent notification),
# set the `show_alert` and `play_sound` parameters to false
# - There are situations where we want silent notifications to play sound.
# In those cases set the `show_alert` to true and `play_sound` to false
# - `checkin_id` parameter is used to create logs, can be set for single user notification
# whenever checkin id is available to the caller.
# - If you want to send a push notification without any expiry set `expiry` to nil.
#
# # send geofence type of notification to multiple users
# user_ids = [12345677, 12345678, 12345679]
# type = PushNotificationService::NOTIFICATION_TYPES[:geofence]
# push_service = PushNotificationService.new(user_ids, type)
# service_response = push_service.perform
#
# # send checkin type of notification to single users
# user_id = 12345677
# type = PushNotificationService::NOTIFICATION_TYPES[:checkin]
# checkin_id = 123
# push_service = PushNotificationService.new(user_id, type, checkin_id)
# service_response = push_service.perform
#
# # send location type of notification to single users with custom expiry value
# user_id = 12345677
# type = PushNotificationService::NOTIFICATION_TYPES[:location]
# checkin_id = 123
# expiry = 5000 # seconds
# push_service = PushNotificationService.new(user_id, type, checkin_id, expiry)
# service_response = push_service.perform
#
# # send silent notification that neither shows alert nor plays sound
# user_id = 12345677
# type = PushNotificationService::LOCATION
# checkin_id = 123
# expiry = APP_CONFIG['push_notification_exipry'] # default value
# show_alert = false
# play_sound = false
# push_service = PushNotificationService.new(user_id, type, checkin_id, expiry, show_alert, play_sound)
# service_response = push_service.perform

class PushNotificationService
  attr_accessor :user_ids, :checkin_id, :type, :expiry, :show_alert, :play_sound

  URBANAIRSHIP_REQUEST_TIMEOUT = 5

  NOTIFICATION_MESSAGES = { geofence: '640', checkin: '610',
                            video_call: '611', missed_video_call: '618',
                            current_location: 'current_location_pn_alert' }

  # TODO: Coordinate with iOS team
  NOTIFICATION_TYPES = {
    geofence: 'geofence',
    geofence_updated: 'geofece_updated', # because iOS team has this key with incorrect spelling thats why
    checkin: 'checkin',
    location: 'location',
    video_call: 'video_call',
    missed_video_call: 'missed_video_call',
    current_location: 'current_location'
  }

  NOTIFICATION_SOUNDS = {
    geofence: 'geofence_alarm.wav',
    geofence_updated: 'alarm_long.wav',
    checkin: 'alarm_long.wav',
    video_call: 'ringing.wav',
    missed_video_call: '',
    current_location: ''
  }

  def initialize(user_ids, type, checkin_id = nil, expiry = APP_CONFIG['push_notification_exipry'],
                 show_alert = true, play_sound = true)

    @user_ids = user_ids
    @checkin_id = checkin_id
    @type = type
    @expiry = expiry
    @show_alert = show_alert
    @play_sound = play_sound

    check_type
    setup_location_notification
  end

  def perform
    setup_client
    response = send_notification
    create_log(response)

    ServiceResult.new response
  end

  private

  def check_type
    return if NOTIFICATION_TYPES.value? @type

    exception_msg = "'type' must be oncee of these values: #{NOTIFICATION_TYPES.keys.join(', ')}"
    fail ArgumentError, exception_msg
  end

  def setup_location_notification
    return unless type.to_s.downcase == 'location'

    # no sound and notification text when type is 'location'
    @show_alert = false
    @play_sound = false
  end

  def setup_client
    @client = Urbanairship::Client.new
    @client.application_key = APP_CONFIG['urban_application_key']
    @client.application_secret = APP_CONFIG['urban_application_secret']
    @client.master_secret = APP_CONFIG['urban_master_secret']
    @client.logger = Rails.logger
    @client.request_timeout = URBANAIRSHIP_REQUEST_TIMEOUT
  end

  def send_notification
    if @user_ids.is_a? Array
      send_bulk_notifications
    else
      send_single_notification
    end
  end

  def send_bulk_notifications
    response = {}

    device_tokens = user_device_tokens

    if device_tokens[:iphone].size > 0
      notification_body = ios_json(device_tokens[:iphone])
      response[:iphone] = @client.push(notification_body)
    end

    if device_tokens[:android].size > 0
      notification_body = android_json(device_tokens[:android])
      response[:android] = @client.push(notification_body)
    end

    response
  end

  def user_device_tokens
    @devices_and_checkins = user_devices_and_checkins

    iphone_device_tokens = []
    android_device_tokens = []

    @devices_and_checkins.each do |d|
      if d.device_type == UserDevice::IPHONE
        iphone_device_tokens.push(d.device_push_token)
      elsif d.device_type == UserDevice::ANDROID
        android_device_tokens.push(d.device_push_token)
      end
    end

    { iphone: iphone_device_tokens, android: android_device_tokens }
  end

  def send_single_notification
    user_device = UserDevice.where(user_id: @user_ids).first
    return {} unless user_device

    notification_body = {}
    if user_device.device_type.to_s.downcase == UserDevice::IPHONE
      notification_body = ios_json(user_device.device_push_token)
    elsif user_device.device_type.to_s.downcase == UserDevice::ANDROID
      notification_body = android_json(user_device.device_push_token)
    end

    response = @client.push(notification_body)

    { response: response, device_push_token: user_device.device_push_token }
  end

  def common_json
    common = {
      audience: {},
      notification: { alert: I18n.t(NOTIFICATION_MESSAGES[@type.to_s.to_sym]) },
      version: APP_CONFIG['urban_api_version'],
      options: {}
    }
    common[:options][:expiry] = @expiry unless @expiry.nil?
    common
  end

  def ios_json(device_push_token)
    ios_json = common_json

    ios_json[:device_types] = ['ios']
    ios_json[:audience][:device_token] = device_push_token
    ios_json[:notification][:ios] = {
      badge: 1,
      extra: extra_json_body
    }

    unless @show_alert
      ios_json[:notification][:ios][:extra][:content_available] = 1
      ios_json[:notification].delete(:alert)
      ios_json[:notification][:ios].delete(:badge)
    end

    if @play_sound
      ios_json[:notification][:ios][:sound] = NOTIFICATION_SOUNDS[@type.to_s.to_sym]
    end

    ios_json
  end

  def android_json(device_push_token)
    android_json = common_json
    android_json[:device_types] = ['android']
    android_json[:audience][:android_channel] = device_push_token
    android_json[:notification][:android] = {
      extra: extra_json_body
    }

    android_json
  end

  def extra_json_body
    extra = {
      type: @type,
      date: "#{DateTime.now.in_time_zone(ZONE)}"
    }

    if @type == NOTIFICATION_TYPES[:video_call]
      call = UserVideoCall.user_call(@user_ids)
      admin_user = AdminUser.find(call.initiated_by)
      extra[:case_manager] = admin_user.first_name + ' ' + admin_user.last_name
    end

    extra
  end

  def user_devices_and_checkins
    select = 'max(user_checkins.id) as checkin_id, user_checkins.user_id, ' \
             'user_devices.device_push_token, user_devices.device_type'

    UserCheckin
      .joins('join user_devices on (user_devices.user_id = user_checkins.user_id)')
      .where("user_checkins.user_id in (#{@user_ids.join(',')})")
      .where("user_checkins.status = 'initiate'")
      .where("ifnull(user_devices.device_push_token, '') != ''")
      .group('user_checkins.user_id')
      .select(select)
  end

  def create_log(response)
    if @user_ids.is_a? Array
      create_bulk_notification_log(response)
    else
      create_single_notification_log(@user_ids, response[:device_push_token],
                                     response[:response], @checkin_id)
    end
  end

  def create_single_notification_log(user_id, device_push_token, response, checkin_id)
    log = LoggedPn.new
    log.user_id = user_id
    log.device_token = device_push_token
    log.is_success = (response.include?(:push_ids) || response.include?(:push_id))
    log.checkin_id = checkin_id if checkin_id
    if response.include?(:details) && response[:details].is_a?(Array)
      log.response = response[:details].first
    else
      log.response = response
    end

    log.save!
  end

  def create_bulk_notification_log(response)
    @devices_and_checkins.each do |d|
      create_single_notification_log(d.user_id, d.device_push_token,
                                     response[d.device_type.to_s.to_sym], d.checkin_id)
    end
  end
end
