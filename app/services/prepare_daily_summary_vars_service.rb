# USAGE:
# This service is meant to be used by 'SendDailySummaryService'
# We have created this service to break a part of 'SendDailySummaryService'
# into a separate independent piece.
#
# prepare_template_vars_service = PrepareDailySummaryTemplateService.new(
#   users_count,
#   total_users_added,
#   total_registrations_pending,
#   total_checkins,
#   missed_checkins_count,
#   complete_checkins_count,
#   user_checkins,
#   geofence_breaches)
#
# response = prepare_template_vars_service.perform
# email_template_vars = response.result

class PrepareDailySummaryVarsService
  attr_accessor :send_test_report

  def initialize(
    users_count,
    total_users_added,
    total_registrations_pending,
    total_checkins,
    missed_checkins_count,
    complete_checkins_count,
    user_checkins,
    geofence_breaches)

    @users_count = users_count
    @total_users_added = total_users_added
    @total_registrations_pending = total_registrations_pending
    @total_checkins = total_checkins
    @missed_checkins_count = missed_checkins_count
    @complete_checkins_count = complete_checkins_count
    @user_checkins = user_checkins
    @geofence_breaches = geofence_breaches
  end

  def perform
    response = email_template_vars
    ServiceResult.new response
  end

  private

  def email_template_vars
    [
      { name: 'fname', content: 'Case Manager' },
      { name: 'enrollees_total', content: @users_count },
      { name: 'enrollees_added', content: @total_users_added },
      { name: 'enrollees_pending_registration', content: @total_registrations_pending },
      { name: 'missed_checkins_total', content: @missed_checkins_count },
      { name: 'complete_checkins_total', content: @complete_checkins_count },
      { name: 'checkins_total', content: @total_checkins },
      { name: 'report_date', content: "#{Time.zone.yesterday.strftime('%m/%d/%Y')}" },
      { name: 'report_items', content: checkins_array_for_email_template(@user_checkins) },
      { name: 'geofence_breaches', content: breaches_array_for_email_template(@geofence_breaches) }
    ]
  end

  def checkins_array_for_email_template(user_checkins)
    checkins = []

    user_checkins.each do |_i, r|
      checkins << prepare_checkin_record_hash(r) if r[:missed].count > 0
    end

    checkins
  end

  def prepare_checkin_record_hash(record)
    user_total_checkins = record[:missed].count + record[:complete].count + record[:partial].count

    record_hash = { record: [{
      name: "#{record[:user_name]}",
      missed_checkins: record[:missed].count,
      checkins: user_total_checkins,
      highlight_missed_checkins: (record[:missed].count / user_total_checkins).round,
      attempts: []
    }] }

    attempt = 1

    record[:missed].each_with_index do |checkin, _i|
      loc = checkin.user_checkin_location.present? ? "#{checkin.user_checkin_location.location}" : 'N/A*'

      record_hash[:record][0][:attempts] << {
        nth_attempt: attempt,
        time: "#{checkin.created_at.strftime('%m/%d/%Y %I:%M %p')}",
        location: loc
      }
      attempt += 1
    end

    record_hash
  end

  def breaches_array_for_email_template(geofence_breaches)
    breaches = []

    geofence_breaches.each do |i, detail|
      breach_hash = {
        name: detail['user_name'],
        breach_number: detail['num_breaches'],
        enrollee_timeline_link: APP_CONFIG['timeline_url'] + i.to_s
      }

      breaches << { breach: [breach_hash] }
    end

    breaches
  end
end
