# USAGE:
#
# # Send daily status report to all case managers whose relevant preferences are set
# send_daily_summary_service = SendDailySummaryService.new
# service_response = send_daily_summary_service.perform
#
# # Send daily status report in Testing mode. Testing Mode sends report to designated QA email only
# send_daily_summary_service = SendDailySummaryService.new(true)
# service_response = send_daily_summary_service.perform
#
# # Get and set object parameters after initialization and before perform
# send_daily_summary_service = SendDailySummaryService.new
# send_daily_summary_service.send_test_report = true
# service_response = send_daily_summary_service.perform

class SendDailySummaryService
  attr_accessor :send_test_report

  REPORT_NAME = 'daily_status_email'

  def initialize(send_test_report = false)
    @send_test_report = send_test_report
  end

  def perform
    @from_date = Time.now.in_time_zone(ZONE) - 15.minutes - 1.day
    @to_date = Time.now.in_time_zone(ZONE) - 15.minutes
    @job_started_at = DateTime.now.in_time_zone(ZONE)

    response = send_daily_status_to_case_mgrs
    create_log

    ServiceResult.new response
  end

  private

  def send_daily_status_to_case_mgrs
    case_managers = AdminUser
                    .joins('join users on (admin_users.id = users.case_manager_id)')
                    .joins('join activate_users on (users.activate_user_id = activate_users.id)')
                    .where('? between activate_users.start_date '\
                           'and ifnull(activate_users.end_date, ?)', @to_date, @to_date)
                    .uniq

    case_managers.each do |case_manager|
      users = User
              .joins('join activate_users on (users.activate_user_id = activate_users.id)')
              .where('? between activate_users.start_date '\
                     'and ifnull(activate_users.end_date, ?)', @to_date, @to_date)
              .where(case_manager_id: case_manager.id)

      emails = all_emails(case_manager)
      next if emails.empty? # move to next iteration if emails is an empty array

      data = prepare_data(users, case_manager.id)
      send_emails(emails, data, users.count)
    end

    {}
  end

  def all_emails(case_manager)
    admin_user_alert_prefs = AdminUserAlerts.get_admin_alerts_preferences(case_manager.id)
    secondary_emails_arr = AdminUserAlerts.get_other_alerts_email_array(case_manager.id)

    emails = []

    if !@send_test_report || (case_manager.email == APP_CONFIG['test_report_recipient_email'])
      if admin_user_alert_prefs.present? && admin_user_alert_prefs.email_daily_digest.present?
        if admin_user_alert_prefs.primary_email_alerts.present? && case_manager.email.present?
          emails << case_manager.email
        end

        if admin_user_alert_prefs.secondary_email_alerts.present? && secondary_emails_arr.present?
          emails.push(*secondary_emails_arr)
        end
      end
    end

    emails
  end

  def prepare_data(users, case_manager_id)
    data = {}

    checkins_data = checkins_stats(case_manager_id)
    data[:checkins_hash] = checkins_data[:checkins_hash]
    data[:total_checkins] = checkins_data[:total_checkins]
    data[:user_checkins] = checkins_data[:user_checkins]

    data[:geofence_breaches] = geofence_breaches_stats(case_manager_id)

    activated_and_registered_data = activated_and_registered_stats(users)
    data[:total_users_added] = activated_and_registered_data[:total_users_added]
    data[:total_registrations_pending] = activated_and_registered_data[:total_registrations_pending]

    data
  end

  def checkins_stats(case_manager_id)
    user_checkins = {}

    total_checkins = 0
    checkins_hash = { missed: 0, complete: 0, partial: 0 }

    checkins_stats = user_checkins_stats(case_manager_id)

    checkins_stats.each do |x|
      if user_checkins[x.user_id].nil?
        user_checkins[x.user_id] = { user_name: nil, missed: [], complete: [], partial: [] }
        user_checkins[x.user_id][:user_name] = "#{x.user.first_name} #{x.user.last_name}"
      end

      user_checkins[x.user_id][x.status.to_sym] << x
      checkins_hash[x.status.to_sym] += 1
      total_checkins += 1
    end

    { checkins_hash: checkins_hash, total_checkins: total_checkins, user_checkins: user_checkins }
  end

  def user_checkins_stats(case_manager_id)
    UserCheckin
      .joins('join users on user_checkins.user_id = users.id')
      .joins('join activate_users on (users.activate_user_id = activate_users.id)')
      .where("users.case_manager_id = #{case_manager_id}")
      .where('? between activate_users.start_date '\
             'and ifnull(activate_users.end_date, ?)', @to_date, @to_date)
      .where(status: %w(missed complete partial))
      .where(created_at: @from_date..@to_date)
      .select('user_checkins.id, user_checkins.user_id, user_checkins.status, '\
                           'user_checkins.created_at')
  end

  def geofence_breaches_stats(case_manager_id)
    geofence_breaches = {}

    geofence_stats = user_geofence_breaches_stats(case_manager_id)

    geofence_stats.each do |x|
      if geofence_breaches[x.user_id].nil?
        geofence_breaches[x.user_id] = { user_name: nil, num_breaches: 0 }
        geofence_breaches[x.user_id]['user_name'] = "#{x.user.first_name} #{x.user.last_name}"
        geofence_breaches[x.user_id]['num_breaches'] = x.num_breaches
      end
    end

    geofence_breaches
  end

  def user_geofence_breaches_stats(case_manager_id)
    GeofenceBreach
      .joins('join users on geofence_breaches.user_id = users.id')
      .joins('join activate_users on (users.activate_user_id = activate_users.id)')
      .where("users.case_manager_id = #{case_manager_id}")
      .where('? between activate_users.start_date '\
             'and ifnull(activate_users.end_date, ?)', @to_date, @to_date)
      .where('geofence_breaches.is_ignored = 0')
      .where(breach_at: @from_date..@to_date)
      .select('geofence_breaches.user_id user_id, count(geofence_breaches.id) num_breaches')
      .group('user_id')
  end

  def activated_and_registered_stats(users)
    total_users_added = 0
    total_registrations_pending = 0

    users.each do |x|
      total_registrations_pending += 1 unless x.is_user_registered

      user_created_at = Time.parse(x.created_at.to_s).in_time_zone(ZONE)
      user_created_today = ActivateUser.where(user_id: x.id, start_date: @from_date..@to_date)
      total_users_added += 1 if user_created_today.count > 0
    end

    {
      total_users_added: total_users_added,
      total_registrations_pending: total_registrations_pending
    }
  end

  def send_emails(emails, data, users_count)
    prepare_template_vars_service = PrepareDailySummaryVarsService.new(
      users_count,
      data[:total_users_added],
      data[:total_registrations_pending],
      data[:total_checkins],
      data[:checkins_hash][:missed],
      data[:checkins_hash][:complete],
      data[:user_checkins],
      data[:geofence_breaches]
    )

    response = prepare_template_vars_service.perform
    email_template_vars = response.result

    subject = "Guardian Daily Summary #{Time.zone.yesterday.strftime('%m/%d/%Y')}"
    template = APP_CONFIG['mandrill_missed_check_ins_report_template']

    emails.each do |email|
      email_service = SendEmailService.new(template, email, subject, email_template_vars, true)
      email_service.perform
    end
  end

  def create_log
    now_in_timezone = DateTime.now.in_time_zone(ZONE)

    log = LoggedCronjob.new

    log.name = REPORT_NAME
    log.start_at = @job_started_at
    log.end_at = now_in_timezone
    log.created_at = now_in_timezone
    log.updated_at = now_in_timezone

    log.save!
  end
end
