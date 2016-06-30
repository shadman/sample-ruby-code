# USAGE:
#
# Returns S3 url of multiple checkins report of the provided user during provided duration
#
# NOTE: The caller must validate that 'to_date' parameter is not greater than 'from_date' parameter
# possibly some way like this in controller:
# return { status: <error_status>, json: <error_json> } unless param[:to] >= param[:from]
#
# user_id = 12345
# from_date = 'some date'
# to_date = 'some date'
# output_type = MultipleCheckinsReportService::OUTPUT_TYPES[:attachment]
# multiple_checkins_report_service = MultipleCheckinsReportService.new(user_id, from_date, to_date,
#                                                                      user_id, output_type)
# service_response = multiple_checkins_report_service.perform
# report_url = service_response.result
#
# # get and set object parameters after initialization and before perform
# user_id = 12345
# from_date = 'some date'
# to_date = 'some date'
# multiple_checkins_report_service = MultipleCheckinsReportService.new(user_id, from_date, to_date)
# multiple_checkins_report_service.user_id = 6789
# service_response = multiple_checkins_report_service.perform
# report_url = service_response.result

class MultipleCheckinsReportService
  attr_accessor :user_id, :from_date, :to_date, :output_type, :offset, :url_expiry_time

  OUTPUT_TYPES = { inline: 'inline', attachment: 'attachment' }
  DATE_FORMAT = '%m-%d-%Y'
  DEFAULT_IMAGE_URL = 'public/blank-avatar.png'

  def initialize(user_id, from_date, to_date, offset = nil, output_type = 'attachment', url_expiry_time = nil)
    @user_id = user_id
    @from_date = from_date.to_datetime
    @to_date = to_date.to_datetime
    @offset = offset
    @output_type = output_type
    @url_expiry_time = url_expiry_time || (Time.now.to_i + APP_CONFIG['report_url_expiry_short'])
  end

  def perform
    report_url = multiple_checkins_report

    if report_url.nil?
      records_not_found_message = I18n.t(408)
      ServiceResult.new nil, false, records_not_found_message
    else
      ServiceResult.new report_url
    end
  end

  private

  def multiple_checkins_report
    inmate = User.find @user_id
    facility = inmate.facility
    format_date_values(facility.time_zone)

    records = ReportGenerator.get_checkins_and_locations(@user_id, @from_date, @to_date)
    return nil unless records.present?

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    filename = prepare_file_name(inmate_display_name, facility)

    ReportGenerator.multiple_checkin_report(records, @from_date, @to_date, @offset, inmate_display_name,
                                            filename, DEFAULT_IMAGE_URL, facility, case_manager_name, inmate)

    upload_file(filename)
    object_url(filename)
  end

  def format_date_values(facility_time_zone)
    @from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from_date, facility_time_zone)
    @to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to_date, facility_time_zone)
  end

  def prepare_file_name(inmate_display_name, facility)
    directory = 'pdfs'
    FileUtils.mkdir directory unless File.directory?(directory)

    date_string = Time.now.in_time_zone(facility.time_zone).strftime(DATE_FORMAT)
    filename = "#{directory}/CheckInsReport_#{inmate_display_name.delete(' ')}_#{date_string}.pdf"

    FileUtils.remove filename if File.file?(filename)

    filename
  end

  def upload_file(filename)
    object_data = File.read filename
    file_storage = FileStorageService.new(FileStorageService::UPLOAD, filename, object_data)
    file_storage.perform
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
