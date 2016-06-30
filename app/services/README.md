This document is created as a common reference for developers to implement service object pattern accross the application:

1. Our service object are plain ruby objects (often called PORO).

2. Location for service classes is 'app/services' and location of their unit tests is 'tests/services'.

3. Service should be of functional nature, a method call should never change the state of the service object.

4. Candidates for service objects are system interactions and wrapper for third party modules. There should not be a service for direct manipulation of business objects as this is the responsibility of models. If a model save or update is a side effect of service call then service should call the relevant model method or vise versa.

5. Every service object does exactly one task and has exactly one public method called 'perform'. This is to keep test cases simple and manageable, and also to conform 'single responsibility principle'.

6. 'perform' method of a service class is an instance methods and not a class methods. This is to avoid concurrency issues and making it thread-safe.

7. For consistency in all 'XService.perform' calls, we pass parameters to object's initializer instead of 'perform' method itself. The initializer sets instance variables which are used when object's 'perform' method is called.

8. For making responses consistent across different services, a service must return an instance of 'ServiceResult'.

9. Ideally our code follows the ruby style guide: https://github.com/bbatsov/ruby-style-guide.

10. Our services do not suppress exceptions by 'rescue'-ing them. If exception is raised they throw it to the caller.

11. Our Services do not validate input parameters like checking email format or character lengths as this is a separate concern.

12. Follow your <3 if there is a scenario not mentioned in this document but do update this document and discuss within the dev team.

13. Example of a new service object:
```ruby
class SendEmailService
  def initialize(subject, recipient)
    @subject = subject
    @recipient = recipient
  end
  def perform
    # do something
    ServiceResult.new
  end
end
```

14. Example of controller call to service:
```ruby
email_service = SendEmailService.new(param1, paramN)
response = email_service.perform
```

[Last modified: 10-Nov-2015]