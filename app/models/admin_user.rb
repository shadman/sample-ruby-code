# == Schema Information
#
# Table name: admin_users

class AdminUser < ActiveRecord::Base
  has_many :users, foreign_key: :case_manager_id
  has_many :user_checkin_comments, foreign_key: :case_manager_id
  has_many :user_video_call_comments, foreign_key: :case_manager_id
  belongs_to :facility

  def self.get_telmate_admin_users(facility_id=0, max_exe_time=30)
    begin
      begin
        Timeout::timeout(max_exe_time) {
          #return Tm::AdminUser.find(:first, :conditions => "facility_id="+facility_id.to_i)
          return Tm::AdminUser.find(:all, :select => "id,DisplayName,login,facility_id,deleted", :conditions => "facility_id=#{facility_id}")
        }
      rescue
        return nil
      end
      return nil
    rescue
      return nil
    end
  end


  def self.get_admin_users_for_facility facility_id
     # user with id '1' and '2' is dummy on prod db and not need here.(GPI-78)
     AdminUser.select('id,label,email')
              .where(facility_id: facility_id)
              .where('id>?', 2)
  end



  def self.get_telmate_admin_user_by_id(user_id=0, max_exe_time=30)
    begin
      begin
        Timeout::timeout(max_exe_time) {
          #return Tm::AdminUser.find(:first, :conditions => "facility_id="+facility_id.to_i)
          return Tm::AdminUser.find(:all, :select => "id,DisplayName,login,facility_id,deleted", :conditions => "id=#{user_id}")
        }
      rescue
        return nil
      end
      return nil
    rescue
      return nil
    end
  end



  def self.insert_users(users)

    created_at = DateTime.now.in_time_zone(ZONE)
    updated_at = created_at

    users.each do|user|

      admin_user = AdminUser.select("id,first_name,last_name,label,facility_id,updated_at").where(id: user.id).first
      name = user.label.split(" ")
      first_name = (name[0])?(name[0].to_s):""
      last_name = ( (name[1])?(name[1].to_s):"" ) + ( (name[2])?(" "+name[2].to_s):"" ) + ( (name[2])?(" "+name[3].to_s):"" )

      if admin_user

        admin_user.update_attributes(
            :updated_at => updated_at,
            :facility_id => user.facility_id,
            :label => user.label,
            :first_name => first_name,
            :last_name => last_name
        )

      else

        unless user.login =~ /^[a-zA-Z][\w\.-]*[a-zA-Z0-9]@[a-zA-Z0-9][\w\.-]*[a-zA-Z0-9]\.[a-zA-Z][a-zA-Z\.]*[a-zA-Z]$/
          email = nil
        else
          email = user.login
        end

        user_save = AdminUser.new(
            :id => user.id,
            :created_at => created_at,
            :updated_at => updated_at,
            :facility_id => user.facility_id,
            :email => email,
            :label => user.label,
            :first_name => first_name,
            :last_name => last_name
        )
        user_save.save

      end




    end

  end


  def self.update_email(id)

    updated_at = DateTime.now.in_time_zone(ZONE)
    admin_user = AdminUser.select(:id).where(id: id).first
    if admin_user
      admin_user.update_attributes(
          :updated_at => updated_at
      )
    end

  end

  def self.update_email_on_active(id,email)

    updated_at = DateTime.now.in_time_zone(ZONE)
    admin_user = AdminUser.select(:id).where(id: id).first
    if admin_user
      admin_user.update_attributes(
          :updated_at => updated_at,
          :email => email
      )
    end

  end


  def self.get_admin_user(user_id)
    AdminUser.where(:id => user_id).first
  end


  def self.get_user_by_username(username)
    AdminUser.where(username: username).first
  end

  def self.get_admin_user_cellphone(user_id)
    self.where(id: user_id).pluck(:cellphone).first
  end

end
