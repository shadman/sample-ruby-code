module GeofenceHelper
  def breach_ignorable?(breach_detail, geofence_id, geofence_time, user_id, datetime_now)
    ignore_checkin = false
    ignore_msg = I18n.t('geofence_ignore_2_hours')

    check_last_breach_time = APP_CONFIG['last_breached_ignore_time']
    last_breached = GeofenceBreach.get_user_last_breached(geofence_id, user_id, datetime_now,
                                                          check_last_breach_time)

    geofence = GeofenceBreach.new
    is_ignorable = geofence.already_reported?(geofence_id,
                                              user_id,
                                              geofence_time,
                                              check_last_breach_time,
                                              datetime_now)
    ignore_msg = I18n.t('geofence_ignore_2 hours_created_at') if is_ignorable

    if last_breached || is_ignorable
      ignore_checkin = true
      geofence.save_ignored_geofence(breach_detail, ignore_msg,geofence_time)
    end
    ignore_checkin
  end
end
