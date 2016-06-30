module V2
  class UserRemindersController < ApplicationController
    before_action :allow_cors
    before_action :restrict_access_admin

    require 'json'

    def create
      user_id = params[:id]
      request_data = JSON.parse(request.body.read)

      validated_resp = UserReminderConfiguration.validate_request(request_data, user_id)
      if validated_resp > 0
        render_error(validated_resp)
        return
      end

      save_data = UserReminderConfiguration.create_reminder(request_data, user_id)
      if save_data
        scheduler_service = DrugCourtReminderSchedulerService.new(user_id, save_data.id)
        scheduler_service.perform
        render_success(200)
      else
        render_error(400)
      end
    end

    def edit
      user_id = params[:id]
      reminder_id = params[:reminder_id]
      request_data = JSON.parse(request.body.read)

      render_error(400) && return unless reminder_id.present?

      validated_resp = UserReminderConfiguration.validate_request(request_data, user_id, reminder_id)
      if validated_resp > 0
        render_error(validated_resp)
        return
      end

      save_data = UserReminderConfiguration.update_reminder(request_data, user_id, reminder_id)
      if save_data
        reschedule_reminders(user_id, reminder_id)
        render_success(200)
      else
        render_error(400)
      end
    end

    def view
      user_id = params[:id]
      reminder_id = params[:reminder_id]

      render_error(400) && return unless reminder_id.present?

      user = User.select('id').find_by_id user_id
      render_error(402) && return if user.blank?

      reminder = UserReminderConfiguration
                 .select('id,title,text,created_by,user_id,event_datetime,reminder_days,reminder_hours,
                         reminder_minutes,is_deleted,is_active,is_expired,last_executed_at,
                         send_event_reminder')
                 .find_by_id(reminder_id)

      render_error(408) && return unless reminder.present?

      render json: { result: reminder }
    end

    def delete
      user_id = params[:id]
      reminder_id = params[:reminder_id]

      render_error(400) && return unless reminder_id.present?

      user = User.select('id').find_by_id user_id
      render_error(402) && return if user.blank?

      reminder = UserReminderConfiguration.select('id')
                 .where(id: reminder_id, user_id: user_id, is_deleted: 0).first
      if reminder.present?
        reminder.is_deleted = 1
        reminder.is_active = 0
        reminder.is_expired = 1
        reminder.save
        UserReminderSchedule.destroy_reminders(user_id, reminder_id)
      else
        render_error(408)
        return
      end
      render_success(205)
    end

    def status
      user_id = params[:id]
      reminder_id = params[:reminder_id]
      status = params[:status]
      validated_resp = UserReminderConfiguration.validation_status(status, user_id)
      if validated_resp > 0
        render_error(validated_resp)
        return
      end
      reminder = UserReminderConfiguration
                 .select('id,is_active')
                 .where(id: reminder_id, user_id: user_id)
                 .first

      render_error(408) && return unless reminder.present?
      desired_status = UserReminderConfiguration.get_reminder_status_value(status)

      render_error(671) && return unless reminder.is_active != desired_status

      reminder.is_active = desired_status
      reminder.save
      UserReminderSchedule.destroy_reminders(user_id, reminder_id) unless desired_status
      render_success(200)
    end

    def list
      user_id = params[:id]
      status = params[:status]

      validated_resp = UserReminderConfiguration.validation_listing(status, user_id)
      if validated_resp > 0
        render_error(validated_resp)
        return
      end

      list = UserReminderConfiguration.get_list_of_reminders(status, user_id)

      if list.present?
        render json: { result: { reminders: list } }
      else
        render json: { result: { reminders: [] } }
      end
    end

  private

    def reschedule_reminders(user_id, reminder_id)
      UserReminderSchedule.destroy_reminders(user_id, reminder_id)
      scheduler_service = DrugCourtReminderSchedulerService.new(user_id, reminder_id)
      scheduler_service.perform
    end
  end
end
