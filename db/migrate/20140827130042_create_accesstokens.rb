class CreateAccesstokens < ActiveRecord::Migration
  def change
    create_table :accesstokens do |t|
      t.belongs_to :application
      t.integer :user_id
      t.string :access_token
      t.datetime :created_on

      t.timestamps
    end
  end
end
