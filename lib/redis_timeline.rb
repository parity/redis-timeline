require 'active_support/concern'
require 'action_controller'
require 'multi_json'
require 'hashie'
require 'timeline/config'
require 'timeline/helpers'
require 'timeline/track'
require 'timeline/actor'
require 'timeline/activity'


module Timeline
  extend Config
  extend Helpers
end

require 'timeline/controller_helper'
require 'timeline/notification_helper'

ActionController::Base.send :include, Timeline::ControllerHelper
ActionController::Base.send :include, Timeline::NotificationHelper
