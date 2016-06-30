module V2
  class VideoCallController < ApplicationController
    before_action :restrict_access_admin, except: [:fetch, :status_mobile, :state]
    before_action :allow_cors, except: [:fetch, :status_mobile, :state]
    before_action :restrict_call, only: [:status_web, :create]

    before_action :restrict_access, :user_is_active, only: [:fetch, :status_mobile, :state]

    # Mobile Endpoints
    def fetch
      render_error(400) and return if request.body.nil?
      payload = JSON.parse(request.body.read).with_indifferent_access
      device_time = device_time_validation(request)
      payload[:is_time_valid] = device_time

      user_call = UserVideoCall.user_call(@logedin_user[:user_id])
      if user_call.present?
        user_call_status = UserVideoCallLocation.call_status(user_call.id)
      else
        render_error_with_status_mobile(632,nil) and return
      end

      # TODO:
      # Need do discuss the error response. Where should the error code be placed. Web and Mobile require different response due
      # to limitation of mobile framework.

      if user_call.present?
        render_error_with_status_mobile(601,user_call) and return if user_call_status.status == UserVideoCall::STATUS[:missed]
        render_error_with_status_mobile(619,user_call) and return if user_call_status.status == UserVideoCall::STATUS[:cancelled]
        render_error_with_status_mobile(632,user_call) and return unless user_call_status.status == UserVideoCall::STATUS[:initiated]

        UserVideoCallLocation.create_call_status(payload, user_call, UserVideoCall::STATUS[:recieved],@logedin_user[:user_id])

        admin_user= AdminUser.find(user_call.initiated_by)
        case_manager = admin_user.first_name + ' ' + admin_user.last_name

        video_session = create_video_session_mobile(user_call.session_id)

        type = APP_CONFIG['location_service']['video_call_fetch']['title']
        Helper::ReconnectionEmailHelper.reconnect_location(@logedin_user[:details], payload[:location], type)

        render status: 200, json: { video_call_id: user_call.id,
                                    session_id: user_call.session_id,
                                    token: video_session.result[:session_mobile_token],
                                    case_manager: case_manager
                          }
      else
        render_error(400) and return
      end
    end

    def state
      call = UserVideoCall.user_call(@logedin_user[:user_id])
      render_error(408) and return if call.nil?

      render status: 200, json: { result: { status: call.status } }
    end

    # Web Endpoints
    def create
      # checking monthly limit for video call
      monthly_limit = APP_CONFIG['video_call_monthly_limit'].to_i * 60
      start_date = Time.zone.today.to_datetime.at_beginning_of_month.to_formatted_s(:db)
      usage = UserVideoCall.monthly_video_call_limit(start_date)
      return render_error('monthly_limit_exceeded') if usage.limit.to_i >= monthly_limit

      UserVideoCall.end_call_if_enrollee_unreachable(@payload['case_manager_id'], @payload['enrollee_id'])
      user_call_status = UserVideoCall.user_ok_to_proceed(@payload['enrollee_id'])
      admin_call_status = UserVideoCall.case_manager_ok_to_proceed(@payload['case_manager_id'])

      return render_error(602) if admin_call_status.present?
      return render_error(603) if user_call_status.present?
      do_video_call(@payload, @user)
    end

    def detail
      call_id = params[:id]

      data = UserVideoCall.get_detail(call_id)
      render_error(408) and return if !data.present?

      # <api_key>/<archived_file_url>/archived.mp4
      if data.uploaded_to_s3.present?
        data.archived_file_url = file_path(data)
      else
        data.archived_file_url = nil
      end

      render status: 200, json: { result: data }
    end

    def download
      call_id = params[:id]
      data = UserVideoCall.get_video_call(call_id)
      render_error(408) and return if !data.present?

      # <api_key>/<archived_file_url>/archived.mp4
      if data.uploaded_to_s3.present?
        data.archived_file_url = file_path(data, 'attachment')
      else
        data.archived_file_url = nil
      end
      render status: 200, json: { result: { url: data.archived_file_url } }
    end

    def list
      user_id = params[:user_id]
      page = params[:page]
      per_page = 20

      records = UserVideoCall.get_call_list(user_id, page, per_page)
      total_records = UserVideoCall.get_calls_count(user_id)
      render status: 200,
             json: { total_records: total_records, per_page_limit: per_page, result: records }
    end


    def add_video_call_comment
      req = JSON.parse(request.body.read)
      case_manager_id = req['case_manager_id']
      user_video_call_id = params['id']
      comment = req['comment']

      Rails.logger.debug "Request attributes hash: #{user_video_call_id} #{case_manager_id} #{comment}"

      videocall_comment = UserVideoCallComment.new({
        case_manager_id: case_manager_id,
        user_video_call_id: user_video_call_id,
        comment: comment
      })

      if videocall_comment.valid?
        if videocall_comment.save!
          comments = UserVideoCallComment.add_comment_to_video_call(user_video_call_id)
          render status: 200, json: { result: { comments: comments } }
        end
      else
        render status: 400, json: {
          result: { error: { message: videocall_comment.errors.full_messages, code: 400 } } }
      end
    end

    def fetch_video_call_comment
      video_call_id = params['id']

      video_call_comments = UserVideoCallComment.fetch_video_call_comment(video_call_id)

      if video_call_comments.present?
        render status: 200, json: { result: { comments: video_call_comments } }
        return
      else
        render status: 200, json: { result: { comments: [] } }
        return
      end
    end

  private

    # private method mobile
    def create_video_session_mobile(opentok_session_id)
      video_service = CreateVideoSessionMobileService.new(opentok_session_id)
      video_service.perform
    end

    # private method web
    def create_video_session_web(payload)
      video_service = CreateVideoSessionService.new(payload['case_manager_id'], payload['enrollee_id'])
      video_service.perform
    end

    # private method
    def do_video_call(payload, user)
      result = create_video_session_web(payload)

      if result.result.present? && result.success == true
        user_call = create_call_db_entries(payload, result, user)
        send_notification(payload, user_call)
      else
        render_error(400)
      end
    end

    # private method
    def send_notification(payload, user_call)
      result = send_video_call_notification(
                 payload['enrollee_id'].to_i,
                 PushNotificationService::NOTIFICATION_TYPES[:video_call])

      if result.result.present? && result.success == true
        success_response(user_call)
      else
        Rails.logger.error result.error[0]
        render_error(400)
      end
    end

    # private method
    def end_call_archiving(archive_file_url)
      archive_stop_service = EndVideoCallArchivingService.new(archive_file_url)
      archive_stop_service.perform
    end

    # private method
    def render_error_with_last_status(status)
      render_error_with_status(400,status)
    end

    # private method
    def send_missed_call_notification(user_call,status)
      if status.upcase == 'MISSED'
        send_video_call_notification(
          user_call.user_id,
          PushNotificationService::NOTIFICATION_TYPES[:missed_video_call]
        )
      end
    end

    # private method
    def send_video_call_notification(enrollee_id, type)
      notification_service = PushNotificationService.new(
        enrollee_id.to_i,
        type
      )

      notification_service.perform
    end

    # private method
    def success_response(user_call)
      render status: 200,
             json: { result:
               { success:
                 {
                   session_id: user_call.session_id, token: user_call.token_id,
                   api_key:APP_CONFIG['opentok_api_key']
                 }
               }
             }
    end

    # private method
    def create_call_db_entries(payload, result, user)
      user_activation = ActivateUser.select(:mode).where(user_id: user.id).last
      is_on_trial = user_activation.mode == 1 ? true : false
      user_call = UserVideoCall.create(
        session_id: result.result[:session_id], token_id: result.result[:session_token],
        user_id: payload['enrollee_id'], initiated_by: payload['case_manager_id'],
        facility_id: user.facility_id, status: UserVideoCall::STATUS[:initiated],
        activate_user_id: user.activate_user_id,
        is_on_trial: is_on_trial
      )

      location_payload = { location:{ latitude:nil, longitude:nil, location:nil } }

      UserVideoCallLocation.create_call_status(location_payload,user_call, UserVideoCall::STATUS[:initiated],payload['case_manager_id'])
      user_call
    end

    # private method
    def file_path(data, type='inline')
      #(APP_CONFIG['s3_image_retrieval_path'].to_s)+"/"+
      options = {
       expires: Time.now.in_time_zone(ZONE).to_i + 600,
       response_content_type: 'video/mp4',
       response_content_disposition: %(#{type}; filename="archived-#{data.id}-#{datetime_now.to_i}.mp4")
      }
      object_key = (APP_CONFIG['opentok_api_key'].to_s)+"/"+(data.archived_file_url.to_s)+"/archive.mp4"
      file_storage = FileStorageService.new(FileStorageService::URL, object_key, options, nil)
      service_response = file_storage.perform
      url = service_response.result
    end

    # private method
    def restrict_call
      @payload = JSON.parse(request.body.read).with_indifferent_access

      @user = User.find_by_id(@payload['enrollee_id'].to_i)
      render_error(402) and return if @user.nil?

      case_manager_id =  @payload['case_manager_id'].present? ? @payload['case_manager_id'].to_i : @user.case_manager_id
      admin_user = AdminUser.find_by_id(case_manager_id)

      render_error(622) and return if admin_user.nil?

      is_user_active = ActivateUser.get_user_activation_period(@user.id, DateTime.now)
      if is_user_active.nil?
        render_error(460) and return
      end

      is_user_registered = User.is_user_registered?(@user.id)
      if is_user_registered.blank?
        render_error(556) and return
      end
    end
  end
end
