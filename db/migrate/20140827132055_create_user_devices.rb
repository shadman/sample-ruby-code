class CreateUserDevices < ActiveRecord::Migration
  def change
    create_table :user_devices do |t|
      t.belongs_to :application
      t.integer :user_id
      t.datetime :created_on
      t.string :device_id
      t.string :device_type

      t.timestamps
    end
  end
end
