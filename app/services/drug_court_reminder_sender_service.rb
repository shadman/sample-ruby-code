# USAGE:
#
# drug_court_reminder_sender_service = DrugCourtReminderSenderService.new
# service_response = drug_court_reminder_sender_service.perform

class DrugCourtReminderSenderService
  def initialize
  end

  def perform
    send_daily_reminders
    ServiceResult.new
  end

  private

  def send_daily_reminders
    from = DateTime.now.in_time_zone - 15.minutes
    to = DateTime.now.in_time_zone
    reminders = UserReminderSchedule.where(date_time: from..to, is_executed: 0)

    reminders.each do |reminder|
      reminder.is_executed = 1
      reminder.executed_at = DateTime.now.in_time_zone.to_s(:db)
      if reminder.save
        user = User.find reminder.user_id
        phone_number = user.cellphone
        text = ' Guardian Reminder: ' + reminder.text.to_s
        sms_service = SendSMSService.new(phone_number, text, reminder.user_id)
        sms_service.perform
      end
    end
  end
end
