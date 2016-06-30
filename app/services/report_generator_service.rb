class ReportGeneratorService
  include Helper
  attr_accessor :to, :from, :user_id, :offset, :id, :type

  def initialize(report_type, options = {})
    @report_type = report_type
    @to = options['to'].nil? ? nil : options['to'].to_datetime
    @from = options['from'].nil? ? nil : options['from'].to_datetime
    @user_id = options['user_id'].nil? ? nil : options['user_id'].to_i
    @offset = options['offset'].nil? ? nil : options['offset']
    @id = options['id'].nil? ? nil : options['id']
    @type = options['type'].nil? ? nil : options['type']
    @app_controller = ApplicationController.new
    @user_controller = V18::UsersController.new
    @url_expire_time = options['expire_time'] || (Time.now.to_i + APP_CONFIG['report_url_expiry_long'])
  end

  def perform
    response = nil
    case @report_type
    when 'checkin_comments'
      response = check_in_comments_report
    when 'view_geofence'
      response = view_geofence_report
    when 'download_geofence'
      response = download_geofence_report
    when 'manifest'
      response = manifest_report
    when 'view_all_checkins'
      response = view_all_check_ins_report
    when 'download_all_checkins'
      response = all_check_ins_report
    when 'view_single_checkin'
      response = view_single_check_in_report
    when 'download_single_checkin'
      response = single_check_in_report
    when 'view_single_checkin_with_bg_data'
      response = view_single_check_in_report_with_bg_data
    when 'download_single_checkin_with_bg_data'
      response = single_check_in_report_with_bg_location
    when 'enrollee_location_report'
      response = enrollee_location_report #services/enrollee_locations_record
    when 'download_user_checkins'
      response = download_user_check_ins_report
    end
    return response
  end

  private

  def check_in_comments_report
    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from
    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)

    object_key = ReportGenerator.check_in_comments_report(inmate, from_date, to_date, facility)

    if object_key.present?
      signed_url = ::Helper::ReportsHelper.get_object_signed_url({
        object_key: object_key,
        response_content_type: 'application/pdf',
        response_content_disposition: %Q(attachment; filename="#{object_key.sub('reports/', '')}"),
        expire_time: @url_expire_time
      })
      return { status: 200, json: { result: { url: signed_url } } }
    else
      return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) }
    end
  end

  def enrollee_location_report
    user = User.find @user_id
    facility = user.facility
    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(402) } unless user.present?

    if @from.present? && @to.present?
      from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
      to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)
    else
      to_date = Time.now
      from_date = (to_date - 1.hour)
    end

    locations = UserLocation.where(user_id: user_id, created_at: from_date..to_date).where.not(latitude: 0, longitude: 0).order('created_at desc')

    if locations.present?
      return { status: 200, json: { result: locations } }
    else
      return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) }
    end
  end

  def manifest_report
    # user_id = params[:id].to_i
    # from = (params[:from].to_datetime)
    # to = (params[:to].to_datetime)
    md5_checksums = {}

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from

    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)

    FileUtils.mkdir 'reports' rescue nil

    completed_report = ReportGenerator.complete_check_ins_manifest(inmate, from_date, to_date, facility)
    missed_report = ReportGenerator.missed_check_ins_manifest(inmate, from_date, to_date, facility)
    voluntary_report = ReportGenerator.voluntary_check_ins_manifest(inmate, from_date, to_date, facility)
    geofence_report = ReportGenerator.geofence_breaches_manifest(inmate, from_date, to_date, facility)
    background_report = ReportGenerator.background_locations_manifest(inmate, from_date, to_date, facility)
    comments_report = ReportGenerator.check_in_comments_report(inmate, from_date, to_date, facility, true)

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)

    zip_file = "zips/ManifestReport_#{inmate_display_name.gsub(' ','')}_#{Date.today.in_time_zone(facility.time_zone).strftime('%m-%d-%Y')}.zip"

    to_zip = "#{completed_report} #{missed_report} #{voluntary_report} #{geofence_report} #{background_report} #{comments_report} "

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } if to_zip.blank?

    to_zip.split.each { |f| md5_checksums[f] = Digest::MD5.hexdigest(File.read(f)) }

    FileUtils.remove zip_file rescue nil #Delete if same name zip file already exists

    check_ins = UserCheckin.joins(:user_checkin_resource).select(:created_at, :audio, :picture).where(user_id: inmate.id, created_at: from_date..to_date)
    FileUtils.mkdir 'audio' rescue nil
    FileUtils.mkdir 'image' rescue nil

    check_ins.each_with_index do |ci, index|
      if ci.audio.present?
        audio = ci.audio

        to_write = ::Helper::ReportsHelper.get_s3_object({ object_key: "#{APP_CONFIG['audio_path']}#{inmate.id}/audios/#{audio}" })

        if to_write.present?
          audio_name = "audio/#{inmate_display_name.gsub(' ','')}_#{ci.created_at.in_time_zone(facility.time_zone).strftime('%Y-%m-%d_%H-%M-%S')}_#{index+1}.mp3"
          File.open("#{audio_name}", 'wb') do |f|
            f.write to_write
          end
          to_zip += "#{audio_name} "
          md5_checksums[audio_name] = Digest::MD5.hexdigest(File.read(audio_name))
        end
      end

      if ci.picture.present?
        pictures = ci.picture.split(',')
        pictures.each_with_index do |p, i|

          to_write = ::Helper::ReportsHelper.get_s3_object({ object_key: "#{APP_CONFIG['audio_path']}#{inmate.id}/images/#{p}" })

          if to_write.present?
            image_name = "image/#{inmate_display_name.gsub(' ','')}_#{ci.created_at.in_time_zone(facility.time_zone).strftime('%Y-%m-%d_%H-%M-%S')}_#{index+1}_#{i+1}.jpg"
            File.open("#{image_name}", 'wb') do |f|
              f.write to_write
            end
            to_zip += "#{image_name} "
            md5_checksums[image_name] = Digest::MD5.hexdigest(File.read(image_name))
          end
        end
      end
    end

    file_list = ReportGenerator.create_file_list(to_zip)
    to_zip += file_list

    ::Helper::ReportsHelper.create_checksum_file(md5_checksums)

    to_zip += ' md5hashes.txt'

    Zip::File.open(zip_file, Zip::File::CREATE) do |zip|
      to_zip.split.each do |filename|
        zip.add(filename, filename)
      end
    end

    object_data = File.read zip_file

    ::Helper::ReportsHelper.set_s3_object({
      object_key: zip_file,
      object_data: object_data
    })

    ::Helper::ReportsHelper.delete_manifest_files(zip_file, file_list)

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: zip_file,
      response_content_type: 'application/zip',
      response_content_disposition: %Q(attachment; filename="#{zip_file.sub('zips/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def user_check_ins_report
    statistics = UserCheckin.user_check_ins_report(@id, @from, @to, @type)
    return { status:200, json: { result: statistics } }
  end

  def single_check_in_report
    check_in = UserCheckin.get_check_in_detail(@id)
    # offset = tz.to_i rescue 0
    inmate = User.find_by_id(check_in.user_id)
    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    facility = inmate.facility
    filename = ::Helper::ReportsHelper.set_file_name('pdfs/CheckInReport',inmate,facility,'pdf')
    zip_file = ::Helper::ReportsHelper.set_file_name('zips/CheckInReport',inmate,facility,'zip')
    image_url = 'public/blank-avatar.png'
    map_image_url = 'http://open.mapquestapi.com/staticmap/v4/getmap?key=Fmjtd|luurn1682u,a2=o5-9wtaur&size=600,300&pois='
    @to_zip = ''

    ReportGenerator.single_checkin_report(check_in, @offset, inmate_display_name, filename, image_url, map_image_url, facility, case_manager_name, inmate)

    @to_zip += ::Helper::ReportsHelper.audio_for_zip(check_in, inmate_display_name, inmate.id)
    @to_zip += ::Helper::ReportsHelper.image_for_zip(check_in, inmate_display_name, inmate.id)

    @to_zip += filename
    FileUtils.remove zip_file rescue nil #Delete if same name zip file already exists
    system("zip #{zip_file} #{@to_zip}")
    system("rm #{@to_zip}")

    object_data = File.read zip_file

    ::Helper::ReportsHelper.set_s3_object({
      object_key: zip_file,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: zip_file,
      response_content_type: 'application/zip',
      response_content_disposition: %Q(attachment; filename="#{zip_file.sub('zips/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def single_check_in_report_with_bg_location
    check_in = UserCheckin.get_check_in_detail(@id.to_i)
    user_id = check_in.user_id
    # from = (from.to_datetime) rescue nil
    # to = ( to.to_datetime) rescue nil
    # offset = tz.to_i rescue 0

    if @from.nil?
      @from = check_in.created_at.beginning_of_day
    end

    if @to.nil?
      @to = check_in.created_at.end_of_day
    end

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless to >= from

    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)

    records = @user_controller.get_checkin_and_locations(check_in.id, @user_id, from_date, to_date, offset)

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } unless records.present?

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    image_url = 'public/blank-avatar.png'
    filename = ::Helper::ReportsHelper.set_file_name('pdfs/CheckInsReport',inmate,facility,'pdf')
    zip_file = ::Helper::ReportsHelper.set_file_name('zips/CheckInReport',inmate,facility,'zip')
    @to_zip = ''

    ReportGenerator.multiple_checkin_report_without_pie_chart(records, @from, @to, @offset, inmate_display_name, filename, image_url, facility, case_manager_name, inmate)

    records.each_with_index do |r, i|
      if r['model'] == 'checkin'
        #check_in = UserCheckin.find r['id']
        @to_zip += ::Helper::ReportsHelper.audio_for_zip(r, inmate_display_name, inmate.id, i+1)
        @to_zip += ::Helper::ReportsHelper.image_for_zip(r, inmate_display_name, inmate.id, i+1)
      end
    end

    @to_zip += filename

    FileUtils.remove zip_file rescue nil #Delete if same name zip file already exists
    system("zip #{zip_file} #{@to_zip}")
    system("rm #{@to_zip}")

    object_data = File.read zip_file

    ::Helper::ReportsHelper.set_s3_object({
      object_key: zip_file,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: zip_file,
      response_content_type: 'application/zip',
      response_content_disposition: %Q(attachment; filename="#{zip_file.sub('zips/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def view_single_check_in_report_with_bg_data
    check_in = UserCheckin.get_check_in_detail(@id.to_i)
    user_id = check_in.user_id
    # from = (from.to_datetime) rescue nil
    # to = (to.to_datetime) rescue nil
    # offset = tz.to_i rescue 0

    if @from.nil?
      # from = DateTime.now.beginning_of_day
      @from = check_in.created_at.beginning_of_day
    end

    if @to.nil?
      @to = check_in.created_at.end_of_day
    end

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from

    inmate = User.find user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(to, facility.time_zone)

    records = @user_controller.get_checkin_and_locations(check_in.id,user_id, from_date, to_date, @offset)

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } unless records.present?

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    image_url = 'public/blank-avatar.png'
    filename = "pdfs/CheckInsReport_#{inmate_display_name.gsub(' ','')}_#{Time.now.in_time_zone(facility.time_zone).strftime('%m-%d-%Y')}.pdf"

    ReportGenerator.multiple_checkin_report_without_pie_chart(records, @from, @to, @offset, inmate_display_name, filename, image_url, facility, case_manager_name, inmate)

    object_data = File.read filename

    ::Helper::ReportsHelper.set_s3_object({
      object_key: filename,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: filename,
      response_content_type: 'application/pdf',
      response_content_disposition: %Q(inline; filename="#{filename.sub('pdfs/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def view_single_check_in_report
    check_in = UserCheckin.get_check_in_detail(@id.to_i)
    # offset = tz.to_i rescue 0
    inmate = check_in.user
    facility = inmate.facility
    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    filename = "pdfs/CheckInReport_#{inmate_display_name.gsub(' ','')}_#{Time.now.in_time_zone(facility.time_zone).strftime('%m-%d-%Y')}.pdf"
    image_url = 'public/blank-avatar.png'
    map_image_url = 'http://open.mapquestapi.com/staticmap/v4/getmap?key=Fmjtd|luu821ub20,7n=o5-94agu0&size=600,300&pois='

    ReportGenerator.single_checkin_report(check_in, @offset, inmate_display_name, filename, image_url, map_image_url, facility, case_manager_name, inmate)

    object_data = File.read filename

    ::Helper::ReportsHelper.set_s3_object({
      object_key: filename,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: filename,
      response_content_type: 'application/pdf',
      response_content_disposition: %Q(inline; filename="#{filename.sub('pdfs/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def all_check_ins_report
    # user_id = params[:id].to_i
    # from = (params[:from].to_datetime)
    # to = (params[:to].to_datetime)
    # offset = params[:tz].to_i rescue 0

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from

    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)

    records = @user_controller.get_checkins_and_locations(@user_id, from_date, to_date, @offset)

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } unless records.present?

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    image_url = 'public/blank-avatar.png'
    filename = ::Helper::ReportsHelper.set_file_name('pdfs/CheckInsReport',inmate,facility,'pdf')
    zip_file = ::Helper::ReportsHelper.set_file_name('zips/CheckInReport',inmate,facility,'zip')
    @to_zip = ''

    ReportGenerator.multiple_checkin_report(records, @from, @to, @offset, inmate_display_name, filename, image_url, facility, case_manager_name, inmate)

    records.each_with_index do |r, i|
      if r['model'] == 'checkin'
        #check_in = UserCheckin.find r['id']
        ::Helper::ReportsHelper.audio_for_zip(r, inmate_display_name, inmate.id, i+1)
        ::Helper::ReportsHelper.image_for_zip(r, inmate_display_name, inmate.id, i+1)
      end
    end

    @to_zip += filename
    FileUtils.remove zip_file rescue nil #Delete if same name zip file already exists
    system("zip #{zip_file} #{@to_zip}")
    system("rm #{@to_zip}")

    object_data = File.read zip_file

    ::Helper::ReportsHelper.set_s3_object({
      object_key: zip_file,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: zip_file,
      response_content_type: 'application/zip',
      response_content_disposition: %Q(attachment; filename="#{zip_file.sub('zips/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def view_all_check_ins_report
    # user_id = params[:id].to_i
    # from = (params[:from].to_datetime) rescue nil
    # to = (params[:to].to_datetime) rescue nil
    # offset = params[:tz].to_i rescue 0

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from

    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)

    records = @user_controller.get_checkins_and_locations(user_id, from_date, to_date, offset)

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } unless records.present?

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    case_manager_name = ::Helper::ReportsHelper.get_user_display_name(inmate.admin_user)
    image_url = 'public/blank-avatar.png'
    filename = "pdfs/CheckInsReport_#{inmate_display_name.gsub(' ','')}_#{Time.now.in_time_zone(facility.time_zone).strftime('%m-%d-%Y')}.pdf"

    ReportGenerator.multiple_checkin_report(records, @from, @to, @offset, inmate_display_name, filename, image_url, facility, case_manager_name, inmate)

    object_data = File.read filename

    ::Helper::ReportsHelper.set_s3_object({
      object_key: filename,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: filename,
      response_content_type: 'application/pdf',
      response_content_disposition: %Q(inline; filename="#{filename.sub('pdfs/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def download_geofence_report
    # user_id = params[:id].to_i
    # from = (params[:from].to_datetime)
    # to = (params[:to].to_datetime)
    # offset = params[:tz].to_i rescue 0

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless to >= from

    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)
    records = GeofenceBreach.list_of_breaches(@user_id, from_date, to_date)
    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } unless records.present?

    inmate_display_name = ::Helper::ReportsHelper.get_user_display_name(inmate)
    filename = "pdfs/GeoFenceReport_#{inmate_display_name.gsub(' ','')}_#{Time.now.in_time_zone(facility.time_zone).strftime('%m-%d-%Y')}.pdf"

    ReportGenerator.geofence_report(inmate, records, @offset, filename)

    object_data = File.read filename

    ::Helper::ReportsHelper.set_s3_object({
      object_key: filename,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: filename,
      response_content_type: 'application/pdf',
      response_content_disposition: %Q(attachment; filename="#{filename.sub('pdfs/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end

  def view_geofence_report
    # user_id = params[:id].to_i
    # from = (params[:from].to_datetime) rescue nil
    # to = (params[:to].to_datetime) rescue nil
    # offset = params[:tz].to_i rescue 0

    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from

    inmate = User.find @user_id
    facility = inmate.facility

    from_date = ::Helper::ReportsHelper.convert_filter_timezone(@from, facility.time_zone)
    to_date = ::Helper::ReportsHelper.convert_filter_timezone(@to, facility.time_zone)
    records = GeofenceBreach.list_of_breaches(@user_id, from_date, to_date)
    return  { status: 200, json: ::Helper::ReportsHelper.get_error_json(408) } unless records.present?

    inmate_display_name =  ::Helper::ReportsHelper.get_user_display_name(inmate)
    filename = "pdfs/GeoFenceReport_#{inmate_display_name.gsub(' ','')}_#{Time.now.in_time_zone(facility.time_zone).strftime('%m-%d-%Y')}.pdf"

    ReportGenerator.geofence_report(inmate, records, @offset, filename)

    object_data = File.read filename

    ::Helper::ReportsHelper.set_s3_object({
      object_key: filename,
      object_data: object_data
    })

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: filename,
      response_content_type: 'application/pdf',
      response_content_disposition: %Q(inline; filename="#{filename.sub('pdfs/', '')}"),
      expire_time: @url_expire_time
    })

    return { status:200, json: { result: { url: signed_url } } }
  end


  def download_user_check_ins_report
    return { status: 200, json: ::Helper::ReportsHelper.get_error_json(499) } unless @to >= @from

    statistics = UserCheckin.user_check_ins_report(@user_id, @from.strftime('%m/%d/%Y') , @to.strftime('%m/%d/%Y'), @type, true)
    return {status: 200, json: ::Helper::ReportsHelper.get_error_json(408)}  unless statistics.present?

    object_key = ReportGenerator.missed_check_ins_report(@user_id, statistics)

    signed_url = ::Helper::ReportsHelper.get_object_signed_url({
      object_key: object_key,
      response_content_type: 'application/pdf',
      response_content_disposition: %Q(attachment; filename="#{object_key.sub('pdfs/', '')}"),
      expire_time: @url_expire_time
    })

    return { json: { result: { url: signed_url } } }
  end

  def touch_configured_statistics
    render_error('time_filter') && return unless params[:days].present?

    filter = params[:days].to_i
    if params[:facility_id].present?
      facility_id = params[:facility_id].to_i
    else
      facility_id = 8083  #Facility ID for Guardian Alpha Test :: Used only for Temp Web Console
    end
    #NOT NEEDED ANYMORE
    if params[:offset].present?
      offset = params[:offset].to_i
    else
      offset = -300  #Offset for Guardian Alpha Test-Karachi office:: Used only for Temp Web Console
    end

    statistics = []

    users = ActivateUser.select(:user_id).distinct

    users.each do |u|
      stats = User.touch_configured_statistics(u.user_id, filter, facility_id, offset)
      statistics << stats unless stats.nil?
    end

    render json: { result: statistics }
  end

  def missed_check_in_statistics
    render_error('time_filter') and return unless params[:days].present?

    filter = params[:days].to_i

    if params[:facility_id].present?
      facility_id = params[:facility_id].to_i
    else
      facility_id = 8083  #Facility ID for Guardian Alpha Test :: Used only for Temp Web Console
    end

    if params[:offset].present?
      offset = params[:offset].to_i
    else
      offset = -300  #Offset for Guardian Alpha Test-Karachi office:: Used only for Temp Web Console
    end

    statistics = []
    total_missed_check_ins = 0
    common_missed_check_in_times = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] #12AM-2AM, 2AM-4AM, 4AM-6AM ... 10PM-12AM
    frequent_missed_time = ''

    users = ActivateUser.select(:user_id).distinct

    users.each do |u|
      stats = User.missed_check_in_statistics(u.user_id, filter, common_missed_check_in_times, facility_id, offset)
      unless stats.nil?
        statistics << stats[0]
        total_missed_check_ins += stats[1]
      end
    end

    frequent_missed_time_index = common_missed_check_in_times.index(common_missed_check_in_times.max)

    case frequent_missed_time_index
    when 0
      frequent_missed_time = '00:00 - 02:00'
    when 1
      frequent_missed_time = '02:00 - 04:00'
    when 2
      frequent_missed_time = '04:00 - 06:00'
    when 3
      frequent_missed_time = '06:00 - 08:00'
    when 4
      frequent_missed_time = '08:00 - 10:00'
    when 5
      frequent_missed_time = '10:00 - 12:00'
    when 6
      frequent_missed_time = '12:00 - 14:00'
    when 7
      frequent_missed_time = '14:00 - 16:00'
    when 8
      frequent_missed_time = '16:00 - 18:00'
    when 9
      frequent_missed_time = '18:00 - 20:00'
    when 10
      frequent_missed_time = '20:00 - 22:00'
    else
      frequent_missed_time = '22:00 - 00:00'
    end

    missed_check_in_enrollees = statistics.count

    render json: { result: { statistics: statistics, missed_check_ins: total_missed_check_ins, missed_check_in_enrollees: missed_check_in_enrollees, frequent_missed_time: frequent_missed_time } }
  end

  def time_series_report
    offset = params[:offset].to_i
    stats = User.time_series_statistics(params[:id], offset)
    if stats.nil?
      render_error(460)
    else
      render json: { result: stats }
    end
  end


end
