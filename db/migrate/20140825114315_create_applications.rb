class CreateApplications < ActiveRecord::Migration
  def change
    create_table :applications do |t|
      t.string :app_name
      t.string :app_key
      t.boolean :status

      t.timestamps
    end
  end
end
