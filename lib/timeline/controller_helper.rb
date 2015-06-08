module Timeline
 
  module ControllerHelper
    def self.included(base)
      base.send :include, InstanceMethods
    end

    module InstanceMethods
      def track_timeline_activity(name, options={})
        @name = name
        @start_value = 0
        @limit_records = (options[:limit_records] && options[:limit_records] > 30) ? options[:limit_records] : 30
        @limit_days = (options[:limit_days] && options[:limit_days] > 30) ? options[:limit_days] : 30
        @actor = options.delete :actor
        @actor ||= :creator
        @object = options.delete :object
        @target = options.delete :target
        @followers = options.delete :followers
        @friends = options.delete :friends
        @mentionable = options.delete :mentionable
       
        @fields_for = {}
        @extra_fields ||= nil
        @merge_similar = options[:merge_similar] == true ? true : false
        options[:verb] = name

        add_activity(activity(verb: options[:verb]))
      end 

      # track_timeline_activity(:new_coupon,actor: :user,object: :coupon_code,followers: :followers)
      
      protected
   
      def activity(options={})
        {
          verb: options[:verb],
          actor: options_for(@actor),
          object: options_for(@object),
          target: options_for(@target),
          created_at: Time.now
        }
      end

      def add_activity(activity_item)
        redis_add "global:activity", activity_item
        redis_add "global:activity:#{activity_item[:verb]}", activity_item
        add_activity_to_user(activity_item[:actor][:id], activity_item)
        add_activity_by_user(activity_item[:actor][:id], activity_item)
        add_mentions(activity_item)
        add_activity_to_followers(activity_item) if @followers.any?
        add_activity_to_friends(activity_item) if @friends.any?
      end

      def add_activity_by_user(user_id, activity_item)
        redis_add "user:id:#{user_id}:posts", activity_item
      end

      def add_activity_to_user(user_id, activity_item)
        redis_add "user:id:#{user_id}:activity", activity_item
      end

      def add_activity_to_users_friends(user_id, activity_item)
        redis_add "user:id:#{user_id}:activity:friends", activity_item
      end

      def add_activity_to_followers(activity_item)
        @followers.each { |follower| add_activity_to_user(follower.id, activity_item) }
      end

      def add_activity_to_friends(activity_item)
        @friends.each { |friend| add_activity_to_users_friends(friend, activity_item) }
      end

      def add_mentions(activity_item)
        return unless @mentionable and @object.send(@mentionable)
        @object.send(@mentionable).scan(/@\w+/).each do |mention|
          if user = @actor.class.find_by_username(mention[1..-1])
            add_mention_to_user(user.id, activity_item)
          end
        end
      end

      def add_mention_to_user(user_id, activity_item)
        redis_add "user:id:#{user_id}:mentions", activity_item
      end

      def extra_fields_for(object)
        return {} unless @fields_for.has_key?(object.class.to_s.downcase.to_sym)
        @fields_for[object.class.to_s.downcase.to_sym].inject({}) do |sum, method|
          sum[method.to_sym] = @object.send(method.to_sym)
          sum
        end
      end

      def options_for(target)
        if !target.nil?
          {
            id: target.id,
            class: target.class.to_s,
            display_name: target.to_s
          }.merge(extra_fields_for(target))
        else
          nil
        end
      end

      def redis_add(list, activity_item)
        Timeline.redis.lpush list, Timeline.encode(activity_item)
        trim_activities list
      end

      def trim_activities(list)
        return if (Timeline.redis.llen list) < @limit_records
        last_record = get_record(list, -1)
        return if (last_record && last_record["created_at"]) > Time.now - @limit_days.days
        trim_old_activities(list)
      end

      def get_record(list, index)
        last_record = Timeline.redis.lindex list, index
        last_record = Timeline.decode(last_record) if last_record
      end

      def trim_old_activities(list)
        Timeline.redis.ltrim list , 0 , get_trim_index(list, (Timeline.redis.llen list) - 1)
      end

      def get_trim_index(list, index)
        return @limit_records if index < @limit_records
        record = get_record(list, index)
        if record && (record["created_at"] < Time.now - @limit_days.days)
          return get_trim_index(list, index - 5)
        else
          return index
        end
      end

      def set_object(object)
        case
        when object.is_a?(Symbol)
          send(object)
        when object.is_a?(Array)
          @fields_for[self.class.to_s.downcase.to_sym] = object
          self
        else
          self
        end
      end
    end
  end

     
end
