class AddCheckInScheduleTable < ActiveRecord::Migration
  def change
    create_table :user_checkin_schedules do |t|
      t.integer :user_id, :limit => 11
      t.date :date
      t.time :time
      t.integer :response_time
      t.text :comments
      t.integer :created_by, :limit => 11
      t.boolean :is_executed

      t.timestamps
    end
  end
end
