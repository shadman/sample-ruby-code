class CreateCheckins < ActiveRecord::Migration
  def change
    create_table :checkins do |t|
      t.integer :user_id
      t.datetime :checkin_start
      t.datetime :checkin_end

      t.timestamps
    end
  end
end
