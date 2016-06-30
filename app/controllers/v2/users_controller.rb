module V2
  class UsersController < ApplicationController
    include ActionController::Live

    # web actions
    before_action :restrict_access_admin, :allow_cors, only: [
      :enrollee, :enrollee_edit, :enrollees_list, :enrollee_checkins, :multiple_enrollee_checkins,
      :user_locations, :user_locations_limited_fields, :location_detail, :all_locations,
      :all_enrollee_checkins, :activate_status, :all_casemanagers , :all_configurations,
      :user_statistics, :user_create, :activate_user, :all_check_ins_report, :view_all_check_ins_report,
      :download_geofence_report, :view_geofence_report, :user_checkin_photo, :device_log_request,
      :reset_user_voice_compare_sample, :export_kml, :deactivate_user, :get_user_contact_info,
      :set_user_contact_info, :download_single_check_in_report, :view_single_check_in_report]

    # mobile actions
    before_action :restrict_access, :user_is_active,
                  only: [:queue_location, :checkins_log, :user_summary, :send_log]

    before_action :restrict_device_with_invalid_time, only: [:user_summary]

    before_action :validate_api_key, :congifure_twilio, only: [:send_pin_code, :send_pin_code]

    before_action :no_cache, :log_action, :urban_authentication,
                  only: [:queue_location, :checkins_log, :user_summary, :send_pin_code, :send_log]

    # kml element colors
    HEX_GREY = Webservice::HEX_GREY
    HEX_GREEN = Webservice::HEX_GREEN
    HEX_AQUA = Webservice::HEX_AQUA
    HEX_RED = Webservice::HEX_RED

    require 'ruby_kml'
    require 'json'

    # Auto documentation comments are removed from v17 as those were not updated and cluttering the code.
    # Better auto documentation will be added later.

    def send_pin_code
      ActiveRecord::Base.audit_log = true
      ActiveRecord::Base.case_manager_key = APP_CONFIG['audit_log_system_id']
      ActiveRecord::Base.case_manager_object = nil
      ActiveRecord::Base.access_token_object = nil

      access_token = AdminUser.where(id: 1).first
      ActiveRecord::Base.case_manager_object = access_token

      phone_number = params[:cell_number]
      logging_parameters = {"Phone"=> phone_number}

      if phone_number

        user = User.where(cellphone: phone_number).first

        if user
          active_user = user_is_active_by_id_400(user.id)
          if active_user
            render_error(460, logging_parameters)
            return
          end

          # Get pin via TCC
          max_exe_time = APP_CONFIG['max_time_out_seconds']
          inmate = User.get_telmate_enrollee_by_id(user.id, max_exe_time)
          if inmate
            # Update user record on local
            User.update_enrollee(user, inmate)

            pin = inmate.pin
            # Send SMS via twilio
            sms_msg = I18n.t(223) + "#{pin}"
            sms_service = SendSMSService.new(phone_number, sms_msg, user.id)
            sms_result = sms_service.perform

            if sms_result.success
              log_event('SMS Sent', logging_parameters)
              render_success(225, logging_parameters)
            else
              render_error(520, logging_parameters)
            end
          else
            render_error(642, logging_parameters)
          end
        else
          render_error(642, logging_parameters)
        end
      else
        render_error(400, logging_parameters)
      end
    end

    # Details of specific enrollee
    def enrollee
      @user_id = params[:id]

      if @user_id.nil?
        render_error(400)
      else
        @user = User.get_single_enrollee(@user_id)
        if @user.nil?
          render_error(402)
        else
          images = nil
          if !@user.images.nil?
            images = @user.images.split(',')
          end

          user = @user.attributes.to_hash

          if !images.nil? && !images[0].nil?
            user['image'] = APP_CONFIG['s3_image_retrieval_path']+"/"+APP_CONFIG['image_register_path']+(@user.id.to_s)+"/images/"+images[0]
          else
            user['image'] = nil
          end
	        user.delete('images')
          user.delete('lock_version')

          render :json => { :result => user }
          end
      end
    end

    #list of all enrollees of case manager
    def enrollees_list
      case_manager_id = params[:id]

      if case_manager_id.nil? || !case_manager_id.is_a?(Numeric)
        render_error(646)
  	    return
      end

      @users = User.get_case_manager_enrollees(case_manager_id) #all
      user_all = []
      @users.each do |us|
        user = us.attributes.to_hash
        user[:is_device_exists] = (us.device_push_token.present?)?1:0

        # Updating image path
        if !us.images.nil?
          images = us.images.split(',')
          if !images[0].nil?
            user['image'] = APP_CONFIG['s3_image_retrieval_path']+"/"+APP_CONFIG['image_register_path']+(us.id.to_s)+"/images/"+images[0]
          else
            user['image'] = nil
          end
        else
          user['image'] = nil
        end
        user.delete('images')
        user.delete('lock_version')

        user.update(user)
        user_all.append user.update(user)
      end

      render :json => { :result => user_all }
    end

    #all checking of specific enrollee
    def enrollee_checkins
      @checkin_param = params[:id]

      @user_checkin = UserCheckin.get_enrollee_checkins(@checkin_param)

      if @user_checkin.blank?
        if User.find_by_id(@checkin_param)
          render_error(409)
        else
          render_error(402)
        end
      else
        checkins_all = []
        @user_checkin.each do |ci|
          checkin = ci.get_enrollee_checkin_hash
          checkins_all.append checkin
        end

        render :json => { :result => checkins_all }
      end
    end

    def user_locations
      user_id = params[:user_id]
      start_date = params[:start_date]
      end_date = params[:end_date]
      if user_id || start_date || end_date
        formatted_start_date = start_date.to_date
        formatted_end_date = end_date.to_date
        user_locations = UserLocation.get_enrollee_location(formatted_start_date, formatted_end_date, user_id)
        render :json =>   {:result => {:locations => user_locations } }
      else
        render_error(400)
      end
    end

    def user_locations_limited_fields
      user_id = params[:user_id]
      start_date = params[:start_date]
      end_date = params[:end_date]
      offset = params[:tz].to_i rescue 0
      if user_id || start_date || end_date
        formatted_start_date = start_date.to_datetime + offset.minutes
        formatted_end_date = end_date.to_datetime + offset.minutes
        user_locations = UserLocation.get_enrollee_location_limited(formatted_start_date, formatted_end_date, user_id)
        render :json =>   {:result => {:locations => user_locations } }
      else
        render_error(400)
      end
    end

    def location_detail
      location_id = params[:location_id]
      if location_id
        location = UserLocation.find_by_id(location_id)
        if location
          device_log = LoggedDevice.where("bg_location_id = ? and type_id = ?",location_id,1).last
          satellite_info = LoggedSatellite.where("location_id = ?",location_id)
        else
          device_log = nil
        end
        if location
          render :json =>   {:result => {:location => location,:device_log =>  device_log, :satellite_info => satellite_info}}
        else
          render_error(648)
        end
      else
        render_error(400)
      end
    end

    def all_locations
      user_id = params[:user_id]
      if user_id
        locations = UserLocation.where(user_id: user_id).select('id,user_id,latitude,longitude')
        if locations
          render :json =>   {:result => {:locations => locations } }
        else
          render_error(402)
        end
      else
        render_error(400)
      end
    end

    def deactivate_user
      user_id = params[:user_id]
      active_user = is_active_user(user_id, datetime_now)
      if active_user
        active_user.update_attributes(:end_date => datetime_now,:updated_at => datetime_now)
        user = User.find_by_id(user_id)
        if user
          reset_all_stuff_of_enrollee(user, user_id)
        else
          render_error(402)
        end
        render_success(200)
        return
      else
        render_error(510)
      end
    end

    def all_casemanagers
      facility_id = params[:facility_id].to_i

      if APP_CONFIG['demo_mode'] == 0
        # Getting telmate admin users to insert in our guardian db
        user_admin = AdminUser.get_telmate_admin_users(facility_id)
        # Inserting admin user result into our admin user tables
        AdminUser.insert_users(user_admin) if user_admin && user_admin.count > 0
      end

      case_managers = AdminUser.get_admin_users_for_facility(facility_id)
      render json: { result: { case_managers: case_managers } }
    end

    def all_configurations
      facility_id = params[:facility_id].to_s
      configurations = UserCheckinTouchConfiguration.select('id, title, max_request_per_day, min_request_per_day').where(:facility_id => facility_id)

      if configurations.length>0
        render :json => {:result => { :configurations => configurations  } }
      else
        configurations = UserCheckinTouchConfiguration.select('id, title, max_request_per_day, min_request_per_day').where(:facility_id => 0)
        if configurations
          render :json => {:result => { :configurations => configurations  } }
        else
          render_error(408)
        end
      end
    end

    def user_create
      @req = JSON.parse(request.body.read)
      enrollee_id = @req["enrollee_id"]
      max_exe_time = APP_CONFIG['max_time_out_seconds']

      user = User.get_single_enrollee(enrollee_id)
      user_data = User.get_telmate_enrollee_by_id(enrollee_id, max_exe_time)

      if user_data.nil? && APP_CONFIG['demo_mode']==1
        render_error(490)
        return
      end

      if user
        if user_data
          User.update_enrollee(user, user_data, @logedin_user)
          render_success(220)
        else
          render_error(402)
        end
      else
        if user_data
          User.create_enrollee(user_data, @logedin_user, @logedin_user[:user_id])
          render_success(218)
        else
          render_error(402)
        end
      end
    end

    def view_single_check_in_report
      check_in_id = params[:id].to_i
      bg_locations = params[:bg]
      from = (params[:from].to_datetime) rescue nil
      to = (params[:to].to_datetime) rescue nil
      offset = params[:tz].to_i rescue 0
      output_type = SingleCheckinReportService::OUTPUT_TYPES[:inline]
      with_files = false

      result = single_check_in_report(check_in_id, from, to, offset, output_type,
                                      with_files, bg_locations)

      render status: 200, json: result
    end

    def download_single_check_in_report
      check_in_id = params[:id].to_i
      bg_locations = params[:bg]
      from = (params[:from].to_datetime) rescue nil
      to = (params[:to].to_datetime) rescue nil
      offset = params[:tz].to_i rescue 0
      output_type = SingleCheckinReportService::OUTPUT_TYPES[:attachment]
      with_files = true

      result = single_check_in_report(check_in_id, from, to, offset, output_type,
                                      with_files, bg_locations)

      render status: 200, json: result
    end

    def single_check_in_report(check_in_id, from, to, offset, output_type, with_files, bg_locations)
      check_in = UserCheckin.get_check_in_detail(check_in_id)
      with_bg_locations = false
      result = nil
      if bg_locations == 'on'
        from = check_in.created_at.beginning_of_day if from.nil?
        to = check_in.created_at.end_of_day if to.nil?
        with_bg_locations = true
      end

      return ::Helper::ReportsHelper.get_error_json(408) if check_in.nil?
      return ::Helper::ReportsHelper.get_error_json(499) unless to >= from

      if (from..to).to_a.length > 7
        user_id = check_in.user_id
        user = User.select(:id, :case_manager_id).find_by(id: user_id)
        case_manager = user.admin_user if user

        return get_error_json(477) if case_manager.email.blank?

        ReportGenerationWorker.perform_async(
          'single_check_ins',
          { 'user_id' => user_id, 'from' => from, 'to' => to, 'offset' => offset, 'check_in_id' => check_in_id,
            'with_files' => with_files, 'with_bg_locations' => with_bg_locations }, case_manager.id)

        return get_success_json('single_checkin_email_success_message')
      end

      single_checkin_rpt_service = SingleCheckinReportService.new(check_in, output_type, with_files,
                                                                  with_bg_locations, from, to, offset)
      service_response = single_checkin_rpt_service.perform
      if service_response.result.nil?
        result = ::Helper::ReportsHelper.get_error_json(408)
      else
        result = { result: { url: service_response.result } }
      end
      result
    end

    def reset_user_voice_compare_sample
      user_id = params['user_id']
      user = User.is_user_exist(user_id)
      if user.nil?
        render_error(402)
      end

      sample = UserVoiceSample.get_active_voice_sample(user_id)
      if sample.present?
        sample.update(is_active: false)
        render_success(200)
      else
        render_error(703)
      end
    end


  private

    def return_checkins_log(checkins)
      if checkins
        checkins_all = []

        checkins.each do |checkin|
          check = checkin.attributes.to_hash
          start_time = (checkin.start_at)?(checkin.start_at.to_i):0
          end_time = (checkin.end_at)?(checkin.end_at.to_i):0
          if checkin.created_at.nil? || checkin.end_at.nil?
            check[:response] =   nil
          else
            check[:response] =   (end_time - checkin.created_at.to_i)
          end
          check[:created_at] = checkin.created_at
          if checkin.start_at
            check[:start_at] = checkin.start_at
          end
          if checkin.end_at
            check[:end_at] = checkin.end_at
          end
          check.update(check)
          checkins_all.append check.update(check)
        end
        if checkins_all.empty?
          render_error(408)
        else
          if params[:page]
            checkins_all_page = Kaminari.paginate_array(checkins_all).page(params[:page]).per(APP_CONFIG['maximum_record_per_page'])
            if checkins_all_page.present?
              page_number = (checkins_all.length.to_f / APP_CONFIG['maximum_record_per_page'].to_f).ceil
              if params[:page].to_i == page_number.to_i
                render :json => { :total_records => checkins_all.length,:per_page_limit => APP_CONFIG['maximum_record_per_page'] , :result => {:logs => checkins_all_page } }
                return
              else
                render :json => { :total_records => checkins_all.length,:per_page_limit => APP_CONFIG['maximum_record_per_page'],:next_page => params[:page].to_i + 1 , :result => {:logs => checkins_all_page } }
                return
              end
            else
              render_error(408)
              return
            end
          end
          render :json =>    {:result => {:logs =>  checkins_all  } }
        end
      else
        render_error(400)
      end
    end

    def add_null_locations (req, user)
      if user.last_bg_location_at.present? && user.last_login_at.present? && user.last_bg_location_at >= user.last_login_at
        time_diff = DateTime.now.in_time_zone(ZONE) - user.last_bg_location_at
      elsif user.last_login_at.present?
        time_diff = DateTime.now.in_time_zone(ZONE) - user.last_login_at
      else
        return req
      end

      if req["offset"]
        offset = req["offset"]
      else
        offset = 10 * 60
      end

      location_expected = (time_diff / offset).floor

      if location_expected > 0
        (0..location_expected).each do |i|
          req["locations"].push({ "accuracy" => "0.000000", "altitude" => "0.000000", "direction" => "0.000000", "latitude" => "0.000000", "location" => "No Location Found", "longitude" => "0.000000", "velocity" => "0.000000" })
        end
      end

      return req
    end

    def is_active_user(user_id, datetime_now)
      ActivateUser.where(:user_id => user_id).where("((start_date <= ? AND end_date >= ?) OR (start_date <= ? AND end_date is ?))", datetime_now, datetime_now,datetime_now, nil).last
    end

    def is_not_active_user(user_id, datetime_now)
      ActivateUser.where(:user_id => user_id).where("end_date <= ? AND end_date IS NOT NULL", datetime_now).last
    end

    def is_active_user_future(user_id, datetime_now)
      ActivateUser.where(:user_id => user_id).where(" start_date > ? ", datetime_now).last
    end

    def generate_user_preference(user_attributes, user_preferences)
      return UserPreferences.generate_frequency(user_attributes) if user_preferences.nil?
      user_attributes[:updated_at] = Helper::DateTimeHelper.datetime_now
      user_preferences.update_frequency(user_attributes)
    end

    def generate_user_attributes(user_id, bg_location_interval)
      { user_id: user_id, bg_location_interval: bg_location_interval }
    end

    def seconds_to_minutes_msg(bg_location_interval)
      return 'Disabled' if bg_location_interval.to_i == 0
      'Every ' + (bg_location_interval.to_i/60).to_s + ' Minutes'
    end

    def check_user_preference_update(current, bg_location_frequency)
      unless bg_location_frequency.nil?
        bg_location_interval = bg_location_frequency.bg_location_interval
        return false if bg_location_interval == current
      end
      return true
    end

  end
end
