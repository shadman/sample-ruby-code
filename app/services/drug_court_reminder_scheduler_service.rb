# USAGE:
#
# user_id = 12345
# reminder_id = 123
# drug_court_reminder_scheduler_service = DrugCourtReminderSchedulerService.new(user_id, reminder_id)
# service_response = drug_court_reminder_scheduler_service.perform
#
# # get and set object parameters after initialization and before perform
# drug_court_reminder_scheduler_service = DrugCourtReminderSchedulerService.new(user_id, reminder_id)
# drug_court_reminder_scheduler_service.reminder_id = 456
# service_response = drug_court_reminder_scheduler_service.perform

class DrugCourtReminderSchedulerService
  attr_accessor :reminder_id, :user_id

  def initialize(user_id, reminder_id)
    @reminder_id = reminder_id
    @user_id = user_id
  end

  def perform
    schedule_daily_reminders
    ServiceResult.new
  end

  private

  def schedule_daily_reminders
    configs = reminders_for_today

    configs.each do |config|
      first_reminder = (config['event_datetime'].to_datetime -
          (config['reminder_days'].to_i).days).strftime('%Y-%m-%d %H:%M:%S')
      second_reminder = (config['event_datetime'].to_datetime -
          (config['reminder_hours'].to_i).hours).strftime('%Y-%m-%d %H:%M:%S')
      third_reminder = (config['event_datetime'].to_datetime -
          (config['reminder_minutes'].to_i).minutes).strftime('%Y-%m-%d %H:%M:%S')

      reminder_list = add_event_reminder(config, config['event_datetime'], first_reminder, second_reminder,
                                         third_reminder)

      UserReminderSchedule.create reminder_list

      update_config(config)

      # Mark job as expired if scheduled because all three reminders fall on the same day.
    end
  end

  def update_config(config)
    config.last_executed_at = DateTime.now.in_time_zone.to_s(:db)
    config.save
  end

  def reminders_for_today
    UserReminderConfiguration
      .where('is_expired' => 0, 'is_active' => 1)
      .where(user_id: @user_id)
      .where(id: @reminder_id)
  end

  def add_event_reminder(config, event_reminder, first_reminder, second_reminder, third_reminder)
    reminder_list = []
    send_reminder = config['send_event_reminder'] ? 1 : nil
    add_reminder(send_reminder, event_reminder, config, reminder_list, 1)
    add_reminder(config['reminder_days'], first_reminder, config, reminder_list, 2)
    add_reminder(config['reminder_hours'], second_reminder, config, reminder_list, 3)
    add_reminder(config['reminder_minutes'], third_reminder, config, reminder_list, 4)

    reminder_list
  end

  def add_reminder(event, event_reminder, config, reminder_list, reminder_type)
    return unless event.present?
    reminder = {
      reminder_type: reminder_type,
      user_id: config['user_id'],
      text: config['text'],
      reminder_id: config['id'],
      activate_user_id: config['activate_user_id'],
      date_time: event_reminder,
      is_executed: 0
    }

    reminder_list << reminder
  end
end
