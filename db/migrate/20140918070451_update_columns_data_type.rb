class UpdateColumnsDataType < ActiveRecord::Migration
  def change
    change_column :user_locations, :user_id, :integer, :limit => 11

    change_column :user_checkins, :user_id, :integer, :limit => 11
    change_column :user_checkins, :created_by, :integer, :limit => 11
    change_column :user_checkins, :longitude_start, :string
    change_column :user_checkins, :longitude_end, :string
    change_column :user_checkins, :latitude_start, :string
    change_column :user_checkins, :latitude_end, :string

    rename_column :accesstokens, :sso_access_token, :telmate_access_token
  end
end
