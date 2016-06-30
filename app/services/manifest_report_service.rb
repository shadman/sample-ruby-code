# USAGE:
#
# Returns S3 url of manifest-report of the provided user during provided duration
#
# NOTE: The caller must validate that 'to_date' parameter is not greater than 'from_date' parameter
# possibly some way like this in controller:
# return { status: <error_status>, json: <error_json> } unless param[:to] >= param[:from]
#
# from_date = 'some date'
# to_date = 'some date'
# user_id = 12345
# offset = 300
# manifest_report_service = ManifestReportService.new(user_id, from_date, to_date, offset)
# service_response = manifest_report_service.perform
# report_url = service_response.result
#
# # get and set object parameters after initialization and before perform
# from_date = 'some date'
# to_date = 'some date'
# user_id = 12345
# manifest_report_service = ManifestReportService.new(user_id, from_date, to_date)
# manifest_report_service.user_id = 6789
# service_response = manifest_report_service.perform
# report_url = service_response.result

class ManifestReportService
  attr_accessor :user_id, :from_date, :to_date, :output_type, :url_expiry_time

  DATE_FORMAT = '%m-%d-%Y'
  DATE_TIME_FORMAT = '%Y-%m-%d_%H-%M-%S'
  OUTPUT_TYPES = { inline: 'inline', attachment: 'attachment' }

  def initialize(user_id, from_date, to_date, url_expiry_time = nil)
    @from_date = from_date.to_datetime
    @to_date = to_date.to_datetime
    @user_id = user_id
    @output_type = output_type
    @url_expiry_time = url_expiry_time || (Time.now.to_i + APP_CONFIG['report_url_expiry_short'])
  end

  def perform
    make_directories

    report_url = manifest_report

    if report_url.nil?
      records_not_found_message = I18n.t(408)
      ServiceResult.new nil, false, records_not_found_message
    else
      ServiceResult.new report_url
    end
  end

  private

  def manifest_report
    inmate = User.find @user_id
    facility = inmate.facility
    format_date_values(facility.time_zone)
    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)

    @files_to_zip = prepare_files_to_zip(inmate, facility)
    return nil if @files_to_zip.blank?

    @md5_checksums = {}
    @files_to_zip.split.each { |f| @md5_checksums[f] = Digest::MD5.hexdigest(File.read(f)) }

    zip_file_name = prepare_zip_file_name(inmate_display_name, facility)

    check_ins = user_check_ins

    check_ins.each_with_index do |ci, index|
      time_string = ci.created_at.in_time_zone(facility.time_zone).strftime(DATE_TIME_FORMAT)
      add_checkin_audio_to_zip(ci.audio, index, inmate_display_name, time_string) if ci.audio.present?
      add_checkin_pics_to_zip(ci.picture, index, inmate_display_name, time_string) if ci.picture.present?
    end

    perform_zip_file_operations(zip_file_name)

    object_url(zip_file_name)
  end

  def make_directories
    %w(reports audio image).each do |name|
      FileUtils.mkdir name unless File.directory?(name)
    end
  end

  def format_date_values(facility_time_zone)
    @from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from_date, facility_time_zone)
    @to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to_date, facility_time_zone)
  end

  def prepare_files_to_zip(inmate, facility)
    completed_rpt = ReportGenerator.complete_check_ins_manifest(inmate, @from_date, @to_date, facility)
    missed_rpr = ReportGenerator.missed_check_ins_manifest(inmate, @from_date, @to_date, facility)
    voluntary_rpt = ReportGenerator.voluntary_check_ins_manifest(inmate, from_date, @to_date, facility)
    geofence_rpt = ReportGenerator.geofence_breaches_manifest(inmate, @from_date, @to_date, facility)
    background_rpt = ReportGenerator.background_locations_manifest(inmate, @from_date, @to_date, facility)
    comments_rpt = ReportGenerator.check_in_comments_report(inmate, @from_date, @to_date, facility, true)

    "#{completed_rpt} #{missed_rpr} #{voluntary_rpt} #{geofence_rpt} #{background_rpt} #{comments_rpt} "
  end

  def prepare_zip_file_name(inmate_display_name, facility)
    date_string = Time.now.in_time_zone(facility.time_zone).strftime(DATE_FORMAT)
    file_name = "zips/ManifestReport_#{inmate_display_name.delete(' ')}_#{date_string}.zip"

    FileUtils.remove file_name if File.file?(file_name)

    file_name
  end

  def user_check_ins
    UserCheckin
      .joins(:user_checkin_resource)
      .where(user_id: @user_id, created_at: @from_date..@to_date)
      .select(:created_at, :audio, :picture)
  end

  def add_checkin_pics_to_zip(picture, index, inmate_display_name, time_string)
    pictures = picture.split(',')

    pictures.each_with_index do |p, i|
      pic_object_key = "#{APP_CONFIG['audio_path']}#{@user_id}/images/#{p}"
      file_storage = FileStorageService.new(FileStorageService::DOWNLOAD, pic_object_key)
      service_response = file_storage.perform
      to_write = service_response.result

      if to_write.present?
        image_name = "image/#{inmate_display_name.delete(' ')}_#{time_string}_#{index + 1}_#{i + 1}.jpg"
        File.open("#{image_name}", 'wb') do |f|
          f.write to_write
        end
        @files_to_zip += "#{image_name} "
        @md5_checksums[image_name] = Digest::MD5.hexdigest(File.read(image_name))
      end
    end
  end

  def add_checkin_audio_to_zip(audio, index, inmate_display_name, time_string)
    audio_object_key = "#{APP_CONFIG['audio_path']}#{@user_id}/audios/#{audio}"
    file_storage = FileStorageService.new(FileStorageService::DOWNLOAD, audio_object_key)
    service_response = file_storage.perform
    to_write = service_response.result

    return unless to_write.present?

    audio_name = "audio/#{inmate_display_name.delete(' ')}_#{time_string}_#{index + 1}.mp3"
    File.open("#{audio_name}", 'wb') do |f|
      f.write to_write
    end
    @files_to_zip += "#{audio_name} "
    @md5_checksums[audio_name] = Digest::MD5.hexdigest(File.read(audio_name))
  end

  def perform_zip_file_operations(zip_file_name)
    file_list = ReportGenerator.create_file_list(@files_to_zip)

    create_checksum_file(file_list)
    add_files_to_zip(zip_file_name)
    upload_zip_file(zip_file_name)
    ::Helper::ReportsHelper.delete_manifest_files(zip_file_name, file_list)
  end

  def create_checksum_file(file_list)
    @files_to_zip += file_list
    @files_to_zip += ' md5hashes.txt'
    ::Helper::ReportsHelper.create_checksum_file(@md5_checksums)
  end

  def add_files_to_zip(zip_file_name)
    Zip::File.open(zip_file_name, Zip::File::CREATE) do |zip|
      @files_to_zip.split.each do |filename|
        zip.add(filename, filename) # TODO: why same parameter twice?
      end
    end
  end

  def upload_zip_file(zip_file_name)
    object_data = File.read zip_file_name
    file_storage = FileStorageService.new(FileStorageService::UPLOAD, zip_file_name, object_data)
    file_storage.perform
  end

  def object_url(filename)
    options = {
      object_key: filename,
      response_content_type: 'application/zip',
      response_content_disposition: %(#{@output_type}; filename="#{filename.sub('zips/', '')}"),
      expires: @url_expiry_time
    }

    file_storage = FileStorageService.new(FileStorageService::URL, filename, options)
    response = file_storage.perform
    response.result
  end
end
