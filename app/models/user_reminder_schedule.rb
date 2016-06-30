class UserReminderSchedule < ActiveRecord::Base
  # Relationships
  belongs_to :user_reminder_configuration
  has_one :user

  include AuditLogs

  def self.destroy_reminders user_id,reminder_id=nil
    if reminder_id.present?
      UserReminderSchedule.where(user_id: user_id,reminder_id: reminder_id, is_executed:0).destroy_all
    else
      UserReminderSchedule.where(user_id: user_id,is_executed:0).destroy_all

    end
  end

end
