module Timeline
 
  module NotificationHelper
    def self.included(base)
      base.send :include, InstanceMethods
    end

    module InstanceMethods
    	def track_notification(name, options={})
    		@name = name
    		@actor = options[:actor]
    		@object = options[:object]
    		@target = options[:target]
        @followers = set_follower(options[:followers])
        @mentionable = options[:mentionable]
        @read = options[:read]

        add_activity_to_subscribed_user(@followers,notification_activity)
        add_mentions(notification_activity)
    	end

    	def add_activity_to_subscribed_user(followers, activity_item)
    		followers.each { |follower| add_to_redis "user:id:#{follower.id}:notification", activity_item}
    	end

    	def add_to_redis(list, activity)
    		Timeline.redis.lpush list, Timeline.encode(activity_item)
  		end

  		def add_mentions(activity_item)
        return unless @mentionable and @object.send(@mentionable)
        @object.send(@mentionable).scan(/@\w+/).each do |mention|
          if user = @actor.class.find_by_username(mention[1..-1])
            add_activity_to_subscribed_user(user, activity_item)
          end
        end
      end

      def set_as_read_notification(user, read, options= {})
  			notifications = get_unread_notification(user, options)
  			notifications.each do |index, notification|
  				$redis.lset("user:id:#{user.id}:notification",index, Timeline.encode(reset_read_activity(notification, read)))
  			end
  		end

  		def get_unread_notification(user, options= {})
		    result = {}
		    $redis.lrange("user:id:#{user.id}:notification", options[:start] || 0, options[:end] || 10).each_with_index do |item, index|
		      data = Timeline.decode(item))
		      result.merge!(index => data) unless data.read
		    end
		    result
		  end


    	private
    	 	def notification_activity
    	 		{
	          verb: @name,
	          actor: @actor,
	          object: @object,
	          target: @target,
	          created_at: Time.now,
	          read: @read
	        }
	    	end

    	 	def set_follower(follower)
	    	 	if follower.is_a?(Array)
	    	 		follower
	    	 	else
	    	 		[follower]
	    	 	end
    	 	end

    	 def reset_read_activity(activity, read)
  			{
	  			verb: activity.verb,
	  			actor: activity.actor,
	  			object: activity.object,
	  			target: activity.target,
	  			created_at: activity.created_at,
	  			read: read
  			}
  		end

    end
  end
end