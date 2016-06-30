# == Schema Information
#
# Table name: user_devices
#
#  id                :integer          not null, primary key
#  application_id    :integer
#  user_id           :integer
#  device_type       :string(255)
#  created_at        :datetime
#  updated_at        :datetime
#  device_push_token :string(255)
#

class UserDevice < ActiveRecord::Base

  # Relationships
  belongs_to :application
  belongs_to :user

  # Usage: UserDevice::ANDROID, UserDevice::IPHONE or UserDevice::DEVICE_TYPES for getting an array of all values
  DEVICE_TYPES = [ ANDROID = 'android', IPHONE = 'iphone' ]

  def self.get_user_devices(user_ids)
    devices, android, iphone = [], [], []
    device_ids = get_device_ids(user_ids)
    if device_ids
      device_ids.each do |device|
        if device.device_type == "android"
          android << device.device_push_token
        else
          iphone << device.device_push_token
        end
      end
    end

    devices << android
    devices << iphone

    return devices
  end

  def self.get_device_ids(ids)
    UserDevice.where(user_id: ids.split(',')).select('device_push_token,device_type').order(id: :desc)
  end

  def self.get_device_id(id)
    UserDevice.where(user_id: id).select('device_push_token,device_type').order(id: :desc)
  end

  def self.add_new_device(user_id,type,push_token)
    dev = UserDevice.new(:application_id => 2,:user_id => user_id,:device_type => type,:device_push_token => push_token)
    dev.save!
  end

  def self.unassign_older_user(device_push_token=nil, device_id)
    if !device_push_token.nil? && device_push_token!=""
      device = UserDevice.where(" device_push_token='"+device_push_token+"' AND id!=#{device_id.to_i}")
      if device
        device.each do |data|
          data.update_attributes(:device_push_token => "")
        end
      end
    end
  end

  def self.user_device_token(user_id)
    UserDevice.where(user_id: user_id).select('device_push_token,device_type').last
  end
end
