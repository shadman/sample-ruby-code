# USAGE:
#
# # End Video Call Archiving
#
# param_1 = Archive ID
#
# video_service = EndVideoCallArchivingService.new(archive_id)
# response = video_service.perform
#

class EndVideoCallArchivingService
  def initialize(archive_id)
    @archive_id = archive_id
  end

  def perform
    session_data = stop_opentok_archiving
    ServiceResult.new(session_data, true, [])
  rescue ::OpenTok::OpenTokError => e
    ServiceResult.new([], false, [e.message])
  end

  private

  def stop_opentok_archiving
    opentok_client = ::OpenTok::OpenTok.new(APP_CONFIG['opentok_api_key'], APP_CONFIG['opentok_api_secret'])
    opentok_client.archives.stop_by_id @archive_id
  end
end
