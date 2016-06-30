class UserPreferences < ActiveRecord::Base

  #Association
  belongs_to :user

  #Attribute validations
  validates :bg_location_interval,
            presence: { message: 'blank_bg_location_interval' },
            numericality: { only_integer: true, message: 'numeric_bg_location_interval'}

  def self.retrieve_frequency(user_id)
    select('id,user_id,created_at,updated_at,bg_location_interval').find_by(user_id: user_id)
  end

  def self.generate_frequency(user_attributes)
    create(user_attributes)
  end

  def update_frequency(user_attributes)
    update_attributes(user_attributes)
  end

  def self.retrieve_bg_location_interval(user_id)
    preferences = retrieve_frequency(user_id)
    user_preference = { bg_location_interval: APP_CONFIG['default_bg_location_interval'] }
    user_preference[:bg_location_interval] = preferences.bg_location_interval unless preferences.nil?
    user_preference
  end

end
