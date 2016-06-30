class TouchConfiguredStatisticsService
  attr_accessor :facility_users, :days

  def initialize(facility_users, days)
    @facility_users = facility_users
    @days = days
  end

  def perform
    touch_configured_statistics
  end

  private

  def touch_configured_statistics
    statistics = []
    user_touch_assignments = UserCheckinTouchAssignment.new
    user_checkin = UserCheckin.new
    key_titles = true

    @facility_users.each do |user|
      assigned_programs = user_touch_assignments.user_assigned_touch(user.id)
      next if assigned_programs.blank?

      checkin_stats = user_checkin.user_checkin_statistics(user.id, @days)
      next if checkin_stats.blank?

      touch_assignments = user_touch_assignments
                          .assigned_touch_program_days_with_type(assigned_programs, key_titles)

      user_stats = user_combined_statistics(checkin_stats, touch_assignments, user)
      statistics << user_stats unless user_stats.nil?
    end
    statistics
  end

  def user_combined_statistics(checkin_stats, touch_assignments, user)
    sent_check_ins = Helper::UtilityHelper.sum_hash_values(checkin_stats)
    missed_percentage = Helper::UtilityHelper.percentage(checkin_stats['missed'], sent_check_ins)

    {
      inmate_id: user.id, user_name: user.full_name,
      touch_programs: touch_assignments,
      check_ins_sent: sent_check_ins,
      completed_check_ins: checkin_stats['complete'],
      partial_check_ins: checkin_stats['partial'],
      missed_check_ins: checkin_stats['missed'],
      missed_percentage: missed_percentage
    }
  end
end
