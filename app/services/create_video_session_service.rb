# USAGE:
#
# # Create Video Session
#
# param_1 = Case Manager ID
# param_2 = Enrollee ID
#
# video_service = CreateVideoSessionService.new(payload['case_manager_id'], payload['enrollee_id'])
# response = video_service.perform
#

class CreateVideoSessionService
  def initialize(case_manager_id, enrollee_id)
    @case_manager_id = case_manager_id
    @enrollee_id = enrollee_id
  end

  def perform
    session_data = create_opentok_session
    session_data.merge!(case_manager_id: @case_manager_id, enrollee_id: @enrollee_id)
    ServiceResult.new(session_data, true, [])
  rescue ::OpenTok::OpenTokError => e
    ServiceResult.new([], false, [e.message])
  end

  private

  def create_opentok_session
    opentok_client = ::OpenTok::OpenTok.new(APP_CONFIG['opentok_api_key'], APP_CONFIG['opentok_api_secret'])
    session = opentok_client.create_session(archive_mode: :always, media_mode: :routed)
    session_token = session.generate_token(
      role: :moderator,
      expire_time: Time.now.to_i + APP_CONFIG['opentok_call_token_duration'],
      data: "case_manager_id=#{@case_manager_id}&enrollee_id=#{@enrollee_id}"
    )
    Rails.logger.info session_token
    { session_id: session.session_id, session_token: session_token }
  end
end
