module ApplicationHelper
  def   get_object_signed_url(options={})
    defaults = {
        bucket_name: "#{APP_CONFIG['s3_bucket_name']}",
        object_key: nil,
        request_type: :get,
        expire_time: Time.now.to_i + 300,
        secure: true,
        force_path_style: false,
        response_content_type: '',
        response_content_disposition: '',
        signature_version: 'v4'
    }

    defaults = defaults.merge(options)

    set_aws_config

    s3_bucket = AWS::S3::Bucket.new(defaults[:bucket_name])

    s3_object = AWS::S3::S3Object.new(s3_bucket, defaults[:object_key])

    presigner = AWS::S3::PresignV4.new(s3_object)

    signed_url = presigner.presign(defaults[:request_type], {expires: defaults[:expire_time], secure: defaults[:secure], force_path_style: defaults[:force_path_style], response_content_type: defaults[:response_content_type], response_content_disposition: defaults[:response_content_disposition], signature_version: defaults[:signature_version]})

    signed_url.to_s
  end

  def set_aws_config(options={})
    defaults = {
        access_key_id: APP_CONFIG['s3_access_key'],
        secret_access_key: APP_CONFIG['s3_secret_key'],
        region: APP_CONFIG['aws_region']
    }

    defaults.merge(options)

    AWS.config(access_key_id: defaults[:access_key_id], secret_access_key: defaults[:secret_access_key], region: defaults[:region])
  end

  def get_s3_client
    set_aws_config
    return AWS::S3::Client::V20060301.new
  end

  def get_s3_object(options={})
    defaults = {
        bucket_name: "#{APP_CONFIG['s3_bucket_name']}",
        object_key: nil
    }

    defaults = defaults.merge(options)

    s3_client = get_s3_client

    response = s3_client.get_object({
                                        bucket_name: defaults[:bucket_name],
                                        key: defaults[:object_key]
                                    })

    if response.successful?
      Rails.logger.info "Asset downloaded from S3 at #{APP_CONFIG['s3_bucket_name']}/#{defaults[:object_key]}"
      return response[:data]
    else
      Rails.logger.error "Asset could not be downloaded from S3 at #{APP_CONFIG['s3_bucket_name']}/#{defaults[:object_key]}"
      return nil
    end
  end

  def set_s3_object(options={})
    defaults = {
        bucket_name: "#{APP_CONFIG['s3_bucket_name']}",
        object_key: nil,
        object_data: nil
    }

    defaults = defaults.merge(options)

    s3_client = get_s3_client

    response = s3_client.put_object({
                                        bucket_name: defaults[:bucket_name],
                                        key: defaults[:object_key],
                                        data: defaults[:object_data]
                                    })

    if response.successful?
      Rails.logger.info "Asset uploaded to S3 at #{APP_CONFIG['s3_bucket_name']}/#{defaults[:object_key]}"
    else
      Rails.logger.error "Asset could not be uploaded to S3"
    end
  end

  # TODO: It should be implemented in model level in refactoring
  def validate_cellphone(cellphone)
    if cellphone.length != 10 || cellphone[0] == '1' || (cellphone !~ /\D/ ) == false || cellphone[0..2].to_i == 0
      false
    else
      true
    end
  end

  def facility_cvb_enabled
    cvb_facility_status = false
    if @facility.present? &&
      @facility.cvb_enabled == true
      cvb_facility_status = true
    end
    cvb_facility_status
  end
end