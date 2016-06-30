class ReconnectLocationService
  attr_accessor :user, :type, :latest_location

  def initialize(user, type, latest_location = nil)
    @user = user
    @type = type
    @latest_location = latest_location
  end

  def perform
    user_reconnect_process
  end

  private

  def user_reconnect_process
    @latest_location = Helper::UtilityHelper.payload_objectify(@latest_location) if @latest_location.present?
    @latest_location = latest_location_from_db if @latest_location.nil?
    return if @latest_location.nil?
    last_location_data_generation

    begin
      reconnection_service = ReconnectionService.new(@user, @type, @latest_location)
      reconnection_service.perform
    rescue StandardError => error
      Rails.logger.info("RECONNECTION EMAIL ERROR: #{error.message}")
    end
  end

  def latest_location_from_db
    location_klass = APP_CONFIG['location_service'][@type]['location_model']
    return location_klass if location_klass.nil?

    user_location = location_klass.constantize.new
    @latest_location = user_location.latest_location(@user.id)
  end

  def last_location_data_generation
    user_attributes = {
      location: @latest_location.location,
      latitude: @latest_location.latitude,
      longitude: @latest_location.longitude,
      is_fake_location: @latest_location.is_fake_location,
      location_type: @type,
      updated_at: Helper::DateTimeHelper.current_datetime
    }
    last_location = UserLastLocation.user_last_location(@user.id)
    if last_location.nil?
      user_attributes[:user_id] = @user.id
      return UserLastLocation.generate_last_location(user_attributes)
    end
    last_location.update_last_location(user_attributes)
  end
end
