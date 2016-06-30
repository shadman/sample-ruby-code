class UpdateDataTypeOfField < ActiveRecord::Migration
  def change
    add_column :user_checkin_schedules, :date_time, :datetime

    remove_column :user_checkin_schedules, :date
    remove_column :user_checkin_schedules, :time
  end
end
