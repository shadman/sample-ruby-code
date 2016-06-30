# USAGE:
#
# # Send email using local templates, (those which reside in app/views/user_mailer)
# recipient_email = 'john.doe@example.com'
# subject = 'email subject here'
# template = 'default.html.erb'
# template_params = { :@name=> 'John Doe' }
# email_service = SendEmailService.new(template, recipient_email, subject, template_params)
# service_response = email_service.perform
#
# # Send email using external templates, the ones which are created on mandrill
# recipient_email = 'john.doe@example.com'
# subject = 'email subject here'
# template = APP_CONFIG['mandrill_missed_check_ins_report_template']
# template_params = [
#   { name: 'fname', content: 'Case Manager'},
#   { name: 'enrollees_total', content: 10 },
#   { name: 'missed_checkins_total', content: 10 },
#   { name: 'complete_checkins_total', content: 10 },
#   { name: 'checkins_total', content: 10 },
#   { name: 'report_date', content: "#{Date.today.strftime('%m/%d/%Y')}" },
#   { name: 'report_items', content: [] }
# ]
# email_service = SendEmailService.new(template, recipient_email, subject, template_params, true)
# service_response = email_service.perform
#
# # get and set object parameters after initialization and before perform
# email_service = SendEmailService.new(template, recipient_email, subject, template_params, true)
# sms_service.recipient_email = 'doe.john@example.com'
# sms_service.subject = 'new subject'
# service_response = email_service.perform

class SendEmailService
  attr_accessor :template, :recipient_email, :subject, :template_params, :is_external_template,
                :attachment, :user_id

  def initialize(template, recipient_email, subject, template_params,
                 is_external_template = false, attachment = nil, user_id = nil)
    @template = template
    @recipient_email = recipient_email
    @subject = subject
    @template_params = template_params
    @is_external_template = is_external_template
    @attachment = attachment
    @user_id = user_id
  end

  def perform
    setup_client
    message = prepare_message
    result = send_email_with_mandrill(message)
    create_log(message)
    ServiceResult.new result, result[:success], result[:err_message]
  end

  private

  def setup_client
    @client = Mandrill::API.new APP_CONFIG['manrill_api_key']
  end

  def prepare_message
    tag_name = Helper::UtilityHelper.tag_format_modifier(@template.dup)
    message = {
      subaccount: APP_CONFIG['mandrill_subaccount'],
      subject: "#{APP_CONFIG['mesg_env_prefix']} #{@subject}",
      from_email: APP_CONFIG['mandrill_from_email'],
      from_name: APP_CONFIG['email_from_name'],
      to: [{ email: "#{@recipient_email}", name: APP_CONFIG['default_email_recipient_name'], type: 'to' }],
      tags: [tag_name, APP_CONFIG['mandril_tag']]
    }

    if @is_external_template
      message[:merge_vars] = [rcpt: @recipient_email, vars: @template_params]
    else
      options = {
        template: "user_mailer/#{@template}",
        layout: false,
        locals: @template_params
      }
      message[:html] = ApplicationController.new.render_to_string(options)
    end

    message[:attachments] = @attachment if @attachment.present?

    message
  end

  def send_email_with_mandrill(message)
    success = true
    err_message = nil
    begin
      async = false
      ip_pool = APP_CONFIG['mandrill_ip_pool']

      if @is_external_template
        @client.messages.send_template @template, @template_params, message, async, ip_pool
      else
        @client.messages.send message, async, ip_pool
      end
    rescue Mandrill::Error => e
      # Mandrill errors are thrown as exceptions
      Rails.logger.info "A mandrill error occurred: #{e.class} - #{e.message}"
      success = false
      err_message = e.message
    end

    { success: success, err_message: err_message }
  end

  def create_log(message)
    content = message[:html] || @template_params
    LoggedEmail.save_log(APP_CONFIG['mandrill_from_email'], @recipient_email, @subject, content, @user_id)
  end
end
