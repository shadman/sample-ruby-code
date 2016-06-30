class VoiceCompareWorker
  include Sidekiq::Worker
  sidekiq_options :queue => (Rails.env + "_voice_compare").to_sym, :backtrace => true
  require 'net/http'


  def perform(checkin_id, user_id)

    access_token = Accesstoken.where(user_id: user_id).first
    ActiveRecord::Base.audit_log = true
    ActiveRecord::Base.case_manager_key = nil
    ActiveRecord::Base.case_manager_object = nil
    ActiveRecord::Base.access_token_object = access_token

    checkin = UserCheckin.find(checkin_id)
    initial_sample = UserVoiceSample.get_active_voice_sample(user_id)
    if !initial_sample.present?
      Rails.logger.info "No voice sample found to compare"
      return true
    end

    initial_checkin = UserCheckinResource.where(:checkin_id => checkin_id).first
    initial_audio = initial_sample.file_path
    initial_checkin_audio= initial_checkin.audio
    app_controller = ApplicationController.new
    
    url = APP_CONFIG['voice_match_app_url'] + "?user_id=#{user_id}&checkin_id=#{checkin_id}&original=#{initial_audio}&compared=#{initial_checkin_audio}&env=#{Rails.env}"
    uri = URI(url)

       begin
        Timeout::timeout(120) {

          res = Net::HTTP.get_response(uri)
          Rails.logger.info res

          if res.code == '200'
            r= JSON.parse(res.body)

            checkin.voice_match_percent = r['match_percentage']
            checkin.voice_reference_id = initial_sample.id
            checkin.save

            if r['match_percentage'].to_i <= 60
             send_low_voice_match_alert(checkin, user_id)
            end

            Rails.logger.info "Checkin updated"
            Rails.logger.info checkin
          else
            raise "Could not complete voice comparison. The voice compare app returned an error : #{res.body}"
          end

        }
      rescue => ex
        raise ex
      end

    app_controller.release_db_connections
  end



  def perform_comparison sample_file_path,checkin_file_path,output,vpExtractor,vpComparator
    Rails.logger.info "Performing Comparison : #{output}"

    cpr = CompareReport.new(sample_file_path, checkin_file_path,'title', output)
    vpA = VoicePrint.new

    vpExtractor.processFile(cpr.prepare_source!, vpA)
    cpr.source_vp = vpA

    parts = cpr.prepare_compare!
    parts.each { |pt|
      pt[3] = VoicePrint.new
      vpExtractor.processFile(pt[1], pt[3])
    }

    parts.each { |pt|
      rawScore = vpComparator.compare2VoicePrints(vpA, pt[3])
      pt[2] =  (100 / (1 + Math.exp(-rawScore)))
      pt[2]
    }
    Rails.logger.info parts
    # cpr.gen_html_report
  end


  def send_low_voice_match_alert(checkin, user_id)
    user = User.select("first_name, last_name, case_manager_id, facility_id").find_by_id(user_id)
    return unless user.admin_user.facility.cvb_enabled

    app_controller = ApplicationController.new
    admin_user_alerts = ::Web::Api::V16::AdminUserAlertsController.new

    user_name =  user.first_name + " " + user.last_name
    timezone = user.facility.time_zone

    case_manager = AdminUser.where(id: user.case_manager_id).select(:first_name, :last_name, :email).first

    checkin_date = checkin.created_at.in_time_zone(timezone).strftime('%m/%d/%Y')
    checkin_time = checkin.created_at.in_time_zone(timezone).strftime('%I:%M %p %Z')
    
    checkin_location = UserCheckinLocation.where(checkin_id: checkin).select(:location, :latitude, :longitude).last

    location = checkin_location.location.present? ? checkin_location.location : checkin_location.latitude.to_s + ", " + checkin_location.longitude.to_s

    alert_params = {enrollee_name: user_name, date: checkin_date, time: checkin_time, location: location}

    Rails.logger.info alert_params

    admin_user_alerts.sms_alert_to_case_manager(user.case_manager_id, APP_CONFIG['sms_admin_alert_types'][5], alert_params)

    var_array = [
                "#{user_name}",
                "#{checkin_date}",
                "#{checkin_time}",
                "#{location}"
                ]

    Rails.logger.info var_array

    is_email_enabled = AdminUserAlerts.get_admin_alerts_preferences(user.case_manager_id)
    if is_email_enabled.present? && is_email_enabled.email_voice_biometric_alert.present?
      
      if is_email_enabled.primary_email_alerts.present?
        app_controller.mandrill('voice_match_alert.html.erb', case_manager.email, 'Enrollee Low Voice Match Alert', var_array, "Case Manager", nil, user_id)
      end

      if is_email_enabled.secondary_email_alerts.present?
        other_email = AdminUserAlerts.get_other_alerts_email_array(user.case_manager_id)

        if other_email.present?
          other_email.each do |email|
            Rails.logger.info "Sending voice match email" + email
            app_controller.mandrill('voice_match_alert.html.erb', email, 'Enrollee Low Voice Match Alert', var_array, "Case Manager", nil, user_id)
          end
        end
      end
      
    end
    

  end

end
