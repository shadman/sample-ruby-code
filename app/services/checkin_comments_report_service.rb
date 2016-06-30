# USAGE:
#
# Returns S3 url of checkin-comment-report of the provided user during provided duration
#
# NOTE: The caller must validate that 'to_date' parameter is not greater than 'from_date' parameter
# possibly someway like this in controller:
# return { status: <error_status>, json: <error_json> } unless param[:to] >= param[:from]
#
# from_date = 'some date'
# to_date = 'some date'
# user_id = 12345
# checkin_comments_report = CheckinCommentsReportService.new(user_id, from_date, to_date)
# service_response = checkin_comments_report.perform
# report_url = service_response.result
#
# # get and set object parameters after initialization and before perform
# from_date = 'some date'
# to_date = 'some date'
# user_id = 12345
# checkin_comments_report = CheckinCommentsReportService.new(user_id, from_date, to_date)
# checkin_comments_report.from_date = 'some other date'
# service_response = checkin_comments_report.perform
# report_url = service_response.result

class CheckinCommentsReportService
  attr_accessor :user_id, :from_date, :to_date, :url_expiry_time

  def initialize(user_id, from_date, to_date, url_expiry_time = nil)
    @from_date = from_date.to_datetime
    @to_date = to_date.to_datetime
    @user_id = user_id
    @url_expiry_time = url_expiry_time || (Time.now.to_i + APP_CONFIG['report_url_expiry_short'])
  end

  def perform
    report_url = check_in_comments_report
    ServiceResult.new report_url
  end

  private

  def check_in_comments_report
    inmate = User.find_by_id @user_id
    facility = inmate.facility
    report_url = nil

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from_date, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to_date, facility.time_zone)

    object_key = ReportGenerator.check_in_comments_report(inmate, from_date, to_date, facility)

    report_url = object_url(object_key) if object_key.present?

    report_url
  end

  def object_url(object_key)
    options = {
      object_key: object_key,
      response_content_type: 'application/pdf',
      response_content_disposition: %(attachment; filename="#{object_key.sub('reports/', '')}"),
      expires: @url_expiry_time
    }

    file_storage = FileStorageService.new(FileStorageService::URL, object_key, options)
    response = file_storage.perform
    response.result
  end
end
