# USAGE:
#
# Returns S3 url of single checkin report for the provided checkin id. This service can also generate
# a checkin report with background location and audio/image with different set of parameters. See below
# examples for 4 different usages of this service:
#
# NOTE: The caller must validate that 'to_date' parameter is not greater than 'from_date' parameter
# possibly some way like this in controller:
# return { status: <error_status>, json: <error_json> } unless param[:to] >= param[:from]
#
# # 1st Example: SIMPLE CHECKIN REPORT WITHOUT LOCATION DATA AND FILES
# checkin_id = 12345
# output_type = SingleCheckinReportService::OUTPUT_TYPES[:attachment]
# single_checkin_report_service = SingleCheckinReportService.new(checkin_id, output_type)
# service_response = single_checkin_report_service.perform
# report_url = service_response.result
#
# # 2nd Example: SIMPLE CHECKIN REPORT WITH AUDIO AND IMAGE FILES
# with_files = true
# single_checkin_report_service = SingleCheckinReportService.new(checkin_id, output_type, with_files)
# # rest of the code same as 1st example
#
# # 3rd Example: CHECKIN REPORT WITH BACKGROUND LOCATION DATA AND WITHOUT FILES
# checkin_id = 12345
# output_type = SingleCheckinReportService::OUTPUT_TYPES[:attachment]
# with_files = false
# with_bg_locations = true
# from_date = 'some date'
# to_date = 'some date'
# offset = nil
# single_checkin_rpt_service = SingleCheckinReportService.new(checkin_id, output_type, with_files,
#                                                                with_bg_locations, from_date, to_date,
#                                                                offset)
# service_response = single_checkin_report_service.perform
# report_url = service_response.result
#
# # 4th Example: CHECKIN REPORT WITH BACKGROUND LOCATION DATA AND AUDIO AND IMAGE FILES
# with_files = true
# single_checkin_report_service = SingleCheckinReportService.new(checkin_id, output_type, with_files,
#                                                                with_bg_locations, from_date, to_date,
#                                                                offset)
# # rest of the code same as 4th example
#
# # Get and set object parameters after initialization and before perform
# checkin_id = 12345
# output_type = SingleCheckinReportService::OUTPUT_TYPES[:attachment]
# single_checkin_report_service = SingleCheckinReportService.new(checkin_id, output_type)
# single_checkin_report_service.checkin_id = 6789
# service_response = single_checkin_report_service.perform
# report_url = service_response.result

class SingleCheckinReportService
  attr_accessor :checkin_id, :output_type, :with_files, :with_bg_locations,
                :from_date, :to_date, :offset, :url_expiry_time

  OUTPUT_TYPES = { inline: 'inline', attachment: 'attachment' }
  DATE_FORMAT = '%m-%d-%Y'
  DEFAULT_IMAGE_URL = 'public/blank-avatar.png'
  MAP_IMAGE_URL = 'http://open.mapquestapi.com/staticmap/v4/getmap'\
                  '?key=Fmjtd|luu821ub20,7n=o5-94agu0&size=600,300&pois='

  def initialize(checkin_id, output_type = 'attachment', with_files = false, with_bg_locations = false,
                 from_date = nil, to_date = nil, offset = nil, url_expiry_time = nil)
    @checkin_id = checkin_id
    @output_type = output_type
    @with_files = with_files
    @with_bg_locations = with_bg_locations
    @from_date = from_date
    @to_date = to_date
    @offset = offset
    @url_expiry_time = url_expiry_time || (Time.now.to_i + APP_CONFIG['report_url_expiry_short'])
  end

  def perform
    make_directories

    report_url = single_checkin_report

    if report_url.nil?
      records_not_found_message = I18n.t(408)
      ServiceResult.new nil, false, records_not_found_message
    else
      ServiceResult.new report_url
    end
  end

  private

  def make_directories
    %w(zips pdfs uploads).each do |name|
      FileUtils.mkdir name unless File.directory?(name)
    end
  end

  def single_checkin_report
    check_in = UserCheckin.get_check_in_detail(@checkin_id)
    return nil unless check_in.present?

    inmate = check_in.user
    facility = inmate.facility
    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)

    if @with_bg_locations
      report_with_bg_location_data(check_in, inmate_display_name, case_manager_name, inmate, facility)
    else
      simple_report(check_in, inmate_display_name, case_manager_name, inmate, facility)
    end
  end

  def report_with_bg_location_data(check_in, inmate_display_name, case_manager_name, inmate, facility)
    filename = prepare_file_name(inmate_display_name, facility)
    format_date_values(check_in, facility.time_zone)

    records = ReportGenerator.get_checkin_and_locations(check_in.id, check_in.user_id, @from_date, @to_date)
    return nil unless records.present?

    ReportGenerator.multiple_checkin_report_without_pie_chart(
      records, @from_date, @to_date, @offset, inmate_display_name, filename,
      DEFAULT_IMAGE_URL, facility, case_manager_name, inmate)

    if @with_files
      zip_filename = prepare_file_name(inmate_display_name, facility, 'zips', 'zip')
      prepare_zip_archive(records, zip_filename, filename, inmate_display_name, inmate.id)

      upload_file(zip_filename)
      object_url(zip_filename, 'zips', 'zip')
    else
      upload_file(filename)
      object_url(filename)
    end
  end

  def simple_report(check_in, inmate_display_name, case_manager_name, inmate, facility)
    filename = prepare_file_name(inmate_display_name, facility)

    ReportGenerator.single_checkin_report(
      check_in, @offset, inmate_display_name, filename, DEFAULT_IMAGE_URL,
      MAP_IMAGE_URL, facility, case_manager_name, inmate)

    if @with_files
      zip_file_name = prepare_file_name(inmate_display_name, facility, 'zips', 'zip')

      to_zip = '' + ::Helper::ReportsHelper.audio_for_zip(check_in, inmate_display_name, inmate.id)
      to_zip += ::Helper::ReportsHelper.image_for_zip(check_in, inmate_display_name, inmate.id)
      to_zip += filename

      system("zip #{zip_file_name} #{to_zip}")
      system("rm #{to_zip}")

      upload_file(zip_file_name)
      object_url(zip_file_name, 'zips', 'zip')
    else
      upload_file(filename)
      object_url(filename)
    end
  end

  def prepare_zip_archive(records, zip_filename, filename, inmate_display_name, inmate_id)
    to_zip = ''
    records.each_with_index do |r, i|
      if r['model'] == 'checkin'
        to_zip += ::Helper::ReportsHelper.audio_for_zip(r, inmate_display_name, inmate_id, i + 1)
        to_zip += ::Helper::ReportsHelper.image_for_zip(r, inmate_display_name, inmate_id, i + 1)
      end
    end
    to_zip += filename

    system("zip #{zip_filename} #{to_zip}")
    system("rm #{to_zip}")
  end

  def format_date_values(checkin, facility_time_zone)
    from = @from_date || checkin.created_at.beginning_of_day
    to = @to_date || checkin.created_at.end_of_day

    @from_date = ::Helper::ReportsHelper.convert_filter_timezone(from, facility_time_zone)
    @to_date = ::Helper::ReportsHelper.convert_filter_timezone(to, facility_time_zone)
  end

  def prepare_file_name(inmate_display_name, facility, directory = 'pdfs', extension = 'pdf')
    [' ', '(', ')'].each { |c| inmate_display_name.delete!(c) }

    date_string = Time.now.in_time_zone(facility.time_zone).strftime(DATE_FORMAT)
    filename = "#{directory}/CheckInReport_#{inmate_display_name}_#{date_string}.#{extension}"

    FileUtils.remove filename if File.file?(filename)

    filename
  end

  def upload_file(filename)
    object_data = File.read filename
    file_storage = FileStorageService.new(FileStorageService::UPLOAD, filename, object_data)
    file_storage.perform
  end

  def object_url(filename, directory = 'pdfs', content_type = 'pdf')
    options = {
      object_key: filename,
      response_content_type: "application/#{content_type}",
      response_content_disposition: %(#{@output_type}; filename="#{filename.sub("#{directory}/", '')}"),
      expires: @url_expiry_time
    }

    file_storage = FileStorageService.new(FileStorageService::URL, filename, options)
    response = file_storage.perform
    response.result
  end
end
