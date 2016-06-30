# USAGE:
#
# Returns enrollee's locaitons during the provided duration.
# Service can be called without date parameters, in that case service returns
# enrollee's location during past one hour.
#
# NOTE: The caller must validate that 'to_date' parameter is not greater than 'from_date' parameter
# possibly some way like this in controller:
# return { status: <error_status>, json: <error_json> } unless param[:to] >= param[:from]
#
# from_date = 'some date'
# to_date = 'some date'
# user_id = 12345
# enrollee_locations_record = EnrolleeLocationsRecordService.new(user_id, from_date, to_date)
# service_response = enrollee_locations_record.perform
# report_url = service_response.result

class EnrolleeLocationsRecordService
  attr_accessor :user_id, :from_date, :to_date

  def initialize(user_id, from_date = nil, to_date = nil)
    @user_id = user_id
    @to_date = to_date
    @from_date = from_date
  end

  def perform
    report = enrollee_locations_record
    ServiceResult.new report
  end

  private

  def enrollee_locations_record
    user = User.find @user_id
    facility = user.facility

    return nil unless user.present?

    if @from_date.present? && @to_date.present?
      from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from_date, facility.time_zone)
      to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to_date, facility.time_zone)
    else
      to_date = Time.now.to_f
      from_date = (to - 1.hour)
    end

    UserLocation
      .where(user_id: user_id, created_at: from_date..to_date)
      .where.not(latitude: 0, longitude: 0)
      .order('created_at desc')
  end
end
