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
        @read = options[:read] || false
        @identifier_key = options[:identifier_key]
        @action = options[:action]
        @extra_info = options[:extra_info] || {}

        if @identifier_key &&  @action
          activity_update_or_create
        else
          add_activity_to_subscribed_user(@followers,notification_activity) if @followers.present?
        end
        add_mentions(notification_activity)
      end

      def activity_update_or_create
        @followers.each do |follower|
          Timeline.redis.lrange("user:id:#{follower.id}:notification", 0, -1).each_with_index do |item, index|
            data = Timeline.decode(item)
            if data["identifier_key"] == @identifier_key && @action == "create"
              Timeline.redis.lrem("user:id:#{follower.id}:notification",index, Timeline.encode(data))
              add_activity_to_subscribed_user([follower],notification_activity)
              break
            elsif data["identifier_key"] == @identifier_key && @action == "update"
              Timeline.redis.lset("user:id:#{follower.id}:notification",index, Timeline.encode(reset_activity(data)))
              break
            end
          end
        end
      end

      def add_activity_to_subscribed_user(followers, activity_item)
        followers.each do |follower|
          add_to_redis "user:id:#{follower.id}:notification", activity_item
          trim_notification "user:id:#{follower.id}:notification"
        end
      end

      def add_to_redis(list, activity_item)
        Timeline.redis.lpush list, Timeline.encode(activity_item)
      end

      def trim_notification(list)
        Timeline.redis.ltrim list, 0, 29
      end

      def add_mentions(activity_item)
        return unless @mentionable
        @mentionable.each do |mention|
          if user = @actor.class.where("coalesce(display_name, login) = ?",mention)
            add_activity_to_subscribed_user(user, activity_item)
          end
        end
      end

      def set_as_read_notification(user, read, options= {})
        notifications = get_unread_notification(user, options)
        notifications.each do |index, notification|
          Timeline.redis.lset("user:id:#{user.id}:notification",index, Timeline.encode(reset_read_activity(notification, read)))
        end
      end

      def get_unread_notification(user, options= {})
        result = {}
        Timeline.redis.lrange("user:id:#{user.id}:notification", options[:start] || 0, options[:end] || 10).each_with_index do |item, index|
          data = Timeline.decode(item)
          result.merge!(index => data) unless data["read"]
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
            read: @read,
            identifier_key: @identifier_key,
            extra_info: @extra_info
          }
        end

        def set_follower(follower)
          if follower.is_a?(Array)
            follower
          elsif follower.present?
            [follower]
          else
            []
          end
        end

        def reset_read_activity(activity, read)
          {
            verb: activity["verb"],
            actor: activity["actor"],
            object: activity["object"],
            target: activity["target"],
            created_at: Time.now,
            read: read,
            identifier_key: activity["identifier_key"],
            extra_info: activity["extra_info"]
          }
        end

        def reset_activity(activity)
          {
            verb: @name || activity["verb"],
            actor: @actor || activity["actor"],
            object: @object || activity["object"],
            target: @target || activity["target"],
            created_at: Time.now,
            read: @read || activity["read"],
            identifier_key: @identifier_key || activity["identifier_key"],
            extra_info: activity["extra_info"].merge(@extra_info)
          }
        end
    end
  end
end
