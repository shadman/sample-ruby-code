class ReportGenerationWorker
  include Sidekiq::Worker
  sidekiq_options queue: ("#{Rails.env}_reports").to_sym, backtrace: true

  def perform(report_type, options, case_manager_id)
    case_manager_obj = AdminUser.where(id: case_manager_id).first
    ActiveRecord::Base.audit_log = true
    ActiveRecord::Base.access_token_object = nil
    ActiveRecord::Base.case_manager_key = case_manager_id
    ActiveRecord::Base.case_manager_object = case_manager_obj

    from = options['from']
    to = options['to']
    user_id = options['user_id']
    options.merge({ expire_time: Time.now.to_i + APP_CONFIG['report_url_expiry_long'] })
    report_url_expiry = Time.now.to_i + APP_CONFIG['report_url_expiry_long']

    case_manager_email = AdminUser.find(case_manager_id).email
    enrollee = User.find(user_id)
    enrollee = "#{enrollee.first_name} #{enrollee.last_name}"
    app_controller = ApplicationController.new

    Rails.logger.info "Reporting worker execution #{options}"

    case report_type
    when 'checkin_comments'
      report_service = CheckinCommentsReportService.new(user_id, from, to, report_url_expiry)
      response = report_service.perform
      report_title = 'Checkin Comments Report'
      subject = "#{report_title} for #{enrollee}"
      report_link = response.result if response.result.present?
      if response.result.blank?
        app_controller.mandrill('send_empty_report.html.erb', case_manager_email, subject, [report_title, enrollee, from.to_date.to_formatted_s(:long), to.to_date.to_formatted_s(:long), nil], 'Guardian', nil, user_id)
        return
      end

    when 'view_geofence'
      output_type = GeofenceReportService::OUTPUT_TYPES[:inline]
      geofence_report_service = GeofenceReportService.new(user_id, from, to, options['offset'], output_type, report_url_expiry)
      response = geofence_report_service.perform
      report_title = 'Geofence Report'
      subject = "#{report_title} for #{enrollee}"
      report_link = response.result if response.result.present?
      if response.result.blank?
        app_controller.mandrill('send_empty_report.html.erb', case_manager_email, subject, [report_title, enrollee, from.to_date.to_formatted_s(:long), to.to_date.to_formatted_s(:long), nil], 'Guardian', nil, user_id)
        return
      end
        
    when 'manifest'
      manifest_report_service = ManifestReportService.new(user_id, from, to, report_url_expiry)
      response = manifest_report_service.perform
      report_title = 'Manifest Report'
      subject = "#{report_title} for #{enrollee}"
      report_link = response.result if response.result.present?
      if response.result.blank?
        app_controller.mandrill('send_empty_report.html.erb', case_manager_email, subject, [report_title, enrollee, from.to_date.to_formatted_s(:long), to.to_date.to_formatted_s(:long), nil], 'Guardian', nil, user_id)
        return
      end

    when 'view_all_checkins'
      output_type = MultipleCheckinsReportService::OUTPUT_TYPES[:inline]
      multiple_check_in_report_service = MultipleCheckinsReportService.new(user_id, from, to, options['offset'],
                                                                           output_type, report_url_expiry)
      response = multiple_check_in_report_service.perform
      report_title = 'All Checkins Report'
      subject = "#{report_title} for #{enrollee}"
      report_link = response.result if response.result.present?
      if response.result.blank?
        app_controller.mandrill('send_empty_report.html.erb', case_manager_email, subject, [report_title, enrollee, from.to_date.to_formatted_s(:long), to.to_date.to_formatted_s(:long), nil], 'Guardian', nil, user_id)
        return
      end

    when 'single_check_ins'
      check_in_id = options['check_in_id']
      with_files = options['with_files']
      with_bg_locations = options['with_bg_locations']
      offset = options['offset']
      from = from.to_datetime
      to = to.to_datetime

      output_type = SingleCheckinReportService::OUTPUT_TYPES[:inline]
      single_checkin_rpt_service = SingleCheckinReportService.new(check_in_id, output_type, with_files,
                                                                  with_bg_locations, from, to, offset,
                                                                  report_url_expiry)
      response = single_checkin_rpt_service.perform
      report_title = I18n.t('worker_single_check_in_report_email_title')
      subject = "#{report_title} for #{enrollee}"
      report_link = response.result if response.result.present?
      if response.result.blank?
        params_email = {
          report_name: report_title,
          enrollee_name_and_device: enrollee,
          time_from: from.to_date.to_formatted_s(:long),
          time_to: to.to_date.to_formatted_s(:long)
        }
        email_service = SendEmailService.new('send_empty_report.html.erb', case_manager_email, subject,
                                             params_email, false, nil, user_id)
        email_service.perform
        return
      end
    else
      report_service = ReportGeneratorService.new report_type, options
      response = report_service.perform
      report_title = 'Report'
      report_link = response[:json][:result][:url]

      case report_type
      when 'view_single_checkin'
        report_title = 'Single Checkin Report'
      when 'view_single_checkin_with_bg_data'
        report_title = 'Single Checkin Report With Background Data'
      when 'enrollee_location_report'
        report_title = 'Enrollee Location Report'
      when 'download_user_checkins'
        report_title = 'Missed Checkin Report'
      end

      subject = "#{report_title} for #{enrollee}"

      if response[:json][:result].key? :error
        app_controller.mandrill('send_empty_report.html.erb', case_manager_email, subject, [report_title, enrollee, from.to_date.to_formatted_s(:long), to.to_date.to_formatted_s(:long), nil], 'Guardian', nil, user_id)
        return
      end
    end

    Rails.logger.info "Response is #{response}"
    template_params = generate_report_email_params(enrollee, from, to, report_link, report_title, subject)
    send_email_service = SendEmailService.new(APP_CONFIG['mandrill_downloadable_reports_template'],
                                              case_manager_email, subject, template_params, true, nil,
                                              user_id)
    send_email_service.perform
  end

  private
  def generate_report_email_params(enrollee, from, to, report_link, report_title, subject)
    time_period = "#{from.to_date.to_formatted_s(:long)} - #{to.to_date.to_formatted_s(:long)}"

    [
      { name: 'subject', content: subject},
      { name: 'fname', content: I18n.t('case_manager')},
      { name: 'report_name', content: report_title},
      { name: 'enrollee_name_and_device', content: enrollee },
      { name: 'time_period', content: time_period },
      { name: 'download_url', content: report_link }
    ]
  end
end
