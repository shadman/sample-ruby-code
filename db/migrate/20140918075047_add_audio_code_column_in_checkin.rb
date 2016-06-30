class AddAudioCodeColumnInCheckin < ActiveRecord::Migration
  def change
    add_column :user_checkins, :audio_code, :string
  end
end
