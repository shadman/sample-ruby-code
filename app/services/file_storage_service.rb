# USAGE:
#
# ## Upload a resource to S3: ##
# object_key = 123456
# data = File.read('/path/to/my/file')
# file_storage = FileStorageService.new(FileStorageService::UPLOAD, object_key, data)
# response = file_storage.perform
#
# ## Download a raw file from S3: ##
# object_key = 123456
# file_storage = FileStorageService.new(FileStorageService::DOWNLOAD, object_key)
# service_response = file_storage.perform
# raw_file = service_response.result
#
# ## Download a raw file from S3 and convert it to base64: ##
# object_key = 123456
# file_storage = FileStorageService.new(FileStorageService::DOWNLOAD, object_key)
# service_response = file_storage.perform
# base64_file = Base64.encode64(service_response.result)
#
# ## Get a resource url from S3 with default options: ##
# object_key = file_path + file_name
# file_storage = FileStorageService.new(FileStorageService::URL, object_key)
# service_response = file_storage.perform
# url = service_response.result
#
# ## Get a resource url from S3 with custom options: ##
# object_key = file_path + file_name
# # see AWS documentation for possible option values
# options = { expires: Time.now.to_i + x, force_path_style: true }
# file_storage = FileStorageService.new(FileStorageService::URL, object_key, options)
# service_response = file_storage.perform
# url = service_response.result

class FileStorageService
  REQUEST_TYPES = [UPLOAD = 'upload', DOWNLOAD = 'download', URL = 'url']
  OUTPUT_TYPES = { inline: 'inline', attachment: 'attachment' }
  DEFAULT_URL_EXPIRY_TIME = Time.now.to_i + 300

  def initialize(type, object_key, object_data = nil, custom_url_options = {})
    @bucket_name = "#{APP_CONFIG['s3_bucket_name']}"
    @type = type
    @object_key = object_key
    @object_data = object_data
    @custom_url_options = custom_url_options

    check_type
  end

  def perform
    setup_client

    if @type == FileStorageService::UPLOAD
      response = upload_file_to_s3
    elsif @type == FileStorageService::DOWNLOAD
      response = download_file_from_s3
    else
      response = s3_file_url
    end

    ServiceResult.new response
  end

  private

  def check_type
    return if REQUEST_TYPES.include? @type

    exception_msg = "'type' must be one of these values: #{REQUEST_TYPES.join(', ')}"
    fail ArgumentError.new, exception_msg
  end

  def setup_client
    AWS.config(access_key_id: APP_CONFIG['s3_access_key'],
               secret_access_key: APP_CONFIG['s3_secret_key'],
               region: APP_CONFIG['aws_region'])

    @client = AWS::S3::Client::V20060301.new
  end

  def s3_file_url
    options = {
      expires: DEFAULT_URL_EXPIRY_TIME,
      secure: true,
      force_path_style: false,
      response_content_type: '',
      response_content_disposition: '',
      signature_version: 'v4'
    }

    options.merge!(@object_data)

    s3_bucket = AWS::S3::Bucket.new(@bucket_name)
    s3_object = AWS::S3::S3Object.new(s3_bucket, @object_key)
    presigner = AWS::S3::PresignV4.new(s3_object)

    url = presigner.presign(:get, options)
    url.to_s
  end

  def upload_file_to_s3
    @client.put_object(bucket_name: @bucket_name, key: @object_key, data: @object_data)
  end

  def download_file_from_s3
    response = @client.get_object(bucket_name: @bucket_name, key: @object_key)

    (response.successful?) ? response[:data] : nil
  end

  def create_log(response)
    return if @type == REQUEST_TYPES[:URL]

    if response.successful?
      message = "Asset #{@type.to_s.downcase}ed to S3 at #{@bucket_name}/#{@object_key}"
    else
      message = "Asset could not be #{@type.to_s.downcase}ed to S3 at #{@bucket_name}/#{@object_key}"
    end

    Rails.logger.error message
  end
end
