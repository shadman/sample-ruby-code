# USAGE:
#
# # Return success response from a service class without response data
# def perform
#   ServiceResult.new
# end
#
# # Return success response from a service class with response data
# def perform
#   # response can be anything which can be returned by a method
#   # for example, array, hash or single value
#   response = { val_one:1, val_two:2 }
#   ServiceResult.new
# end
#
# # Return error response from a service class
# def perform
#   ServiceResult.new nil, false
# end

class ServiceResult
  attr_accessor :success, :result, :errors

  def initialize(result = nil, success = true, errors = [])
    @result = result
    @success = success
    @errors = errors
  end
end
