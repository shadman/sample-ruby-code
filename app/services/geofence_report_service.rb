# USAGE:
#
# Returns S3 url of geofence-report of the provided user during provided duration
#
# NOTE: The caller must validate that 'to_date' parameter is not greater than 'from_date' parameter
# possibly some way like this in controller:
# return { status: <error_status>, json: <error_json> } unless param[:to] >= param[:from]
#
# from_date = 'some date'
# to_date = 'some date'
# user_id = 12345
# offset = 300
# output_type = GeofenceReportService::OUTPUT_TYPES[:attachment]
# geofence_report_service = GeofenceReportService.new(user_id, from_date, to_date, offset, output_type)
# service_response = geofence_report_service.perform
# report_url = service_response.result
#
# # get and set object parameters after initialization and before perform
# from_date = 'some date'
# to_date = 'some date'
# output_type = GeofenceReportService::OUTPUT_TYPES[:attachment]
# geofence_report_service = GeofenceReportService.new(user_id, from_date, to_date, output_type)
# geofence_report_service.output_type = GeofenceReportService::OUTPUT_TYPES[:inline]
# service_response = geofence_report_service.perform
# report_url = service_response.result

class GeofenceReportService
  attr_accessor :user_id, :from_date, :to_date, :output_type, :offset, :url_expiry_time

  OUTPUT_TYPES = { inline: 'inline', attachment: 'attachment' }
  DATE_FORMAT = '%m-%d-%Y'

  def initialize(user_id, from_date, to_date, offset = nil, output_type = 'attachment', url_expiry_time = nil)
    @from_date = from_date.to_datetime
    @to_date = to_date.to_datetime
    @user_id = user_id
    @offset = offset
    @output_type = output_type
    @url_expiry_time = url_expiry_time || (Time.now.to_i + APP_CONFIG['report_url_expiry_short'])
  end

  def perform
    report_url = geofence_report
    ServiceResult.new report_url
  end

  private

  def geofence_report
    inmate = User.find @user_id
    facility = inmate.facility
    facility_timezone = facility.time_zone

    records = geofence_records(facility_timezone)

    return nil unless records.present?

    filename = file_name(inmate, facility_timezone)

    ReportGenerator.geofence_report(inmate, records, @offset, filename)

    object_data = File.read(filename)

    file_uploader = FileStorageService.new(FileStorageService::UPLOAD, filename, object_data)
    file_uploader.perform

    report_url = object_url(filename)

    File.delete(filename)

    report_url
  end

  def geofence_records(time_zone)
    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from_date, time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to_date, time_zone)
    GeofenceBreach.list_of_breaches_by_breach_date(@user_id, from_date, to_date)
  end

  def file_name(inmate, facility_timezone)
    directory = 'pdfs'
    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)

    date_string = Time.now.in_time_zone(facility_timezone).strftime(DATE_FORMAT)
    filename = "#{directory}/GeoFenceReport_#{inmate_display_name.delete(' ')}_#{date_string}.pdf"

    FileUtils.mkdir directory unless File.directory?(directory)

    filename
  end

  def object_url(filename)
    options = {
      object_key: filename,
      response_content_type: 'application/pdf',
      response_content_disposition: %(#{@output_type}; filename="#{filename.sub('pdfs/', '')}"),
      expires: @url_expiry_time
    }

    file_storage = FileStorageService.new(FileStorageService::URL, filename, options)
    response = file_storage.perform
    response.result
  end
end
