# USAGE:
#
# # Create Video Session Mobile
#
# param_1 = OPENTOK SESSION ID
#
# video_service = CreateVideoSessionMobileService.new(user_call.session_id)
# response = video_service.perform
#

class CreateVideoSessionMobileService
  def initialize(opentok_session_id)
    @opentok_session_id = opentok_session_id
  end

  def perform
    session_data = create_opentok_mobile_token
    ServiceResult.new(session_data, true, [])
  rescue ::OpenTok::OpenTokError => e
    ServiceResult.new([], false, [e.message])
  end

  private

  def create_opentok_mobile_token
    opentok_client = ::OpenTok::OpenTok.new(APP_CONFIG['opentok_api_key'], APP_CONFIG['opentok_api_secret'])
    session_mobile_token = opentok_client.generate_token(
      @opentok_session_id,
      {
        role: :publisher,
        expire_time: Time.now.to_i + APP_CONFIG['opentok_call_token_duration'],
        data: "opentok_session_id=#{@opentok_session_id}"
      }
    )
    { session_id: @opentok_session_id, session_mobile_token: session_mobile_token }
  end
end
