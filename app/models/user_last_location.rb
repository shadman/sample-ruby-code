class UserLastLocation < ActiveRecord::Base
  def self.user_last_location(user_id)
    find_by(user_id: user_id)
  end

  def self.generate_last_location(user_attributes)
    create(user_attributes)
  end

  def update_last_location(user_attributes)
    update_attributes(user_attributes)
  end

  def self.last_location_date_time(user_id)
    select('updated_at').find_by(user_id: user_id)
  end
end
