module CfnEvents

  class Runner

    def initialize(config)
      @config = config

      @config.cfn_client ||= begin
                               effective_options = CfnEvents::Client.core_v2_options.merge(config.client_options)
                               Aws::CloudFormation::Client.new(effective_options)
                             end
    end

    def core_v2_options
      i
    end

    def resolve_stack(stack_name_or_id)
      ans = @config.cfn_client.describe_stacks(stack_name: stack_name_or_id).data.stacks[0].stack_id
      if ans != stack_name_or_id
        $stderr.puts "Resolved #{stack_name_or_id} to #{ans}"
      end
      ans
    end

    def all_events
      @config.cfn_client.describe_stack_events(stack_name: @stack_id).data.stack_events.reverse
    end

    def events_since_time(events, t)
      # There may be a more efficient algorithm
      events.select {|e| e.timestamp > t }
    end

    def events_since_id(id)
      # There may be a more efficient algorithm
      events = all_events
      i = events.index {|e| e.event_id == id }
      if i < 0
        events
      else
        events[i+1..-1]
      end
    end

    def show_events(events)
      events.each do |e|
        if @config.output_json
          puts JSON.generate(e.to_h)
        else
          puts [
            e.timestamp.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
            e.resource_type,
            e.resource_status,
            e.logical_resource_id,
            e.physical_resource_id,
            e.resource_status_reason,
          ].join " "
        end
      end
    end

    def steady_state?(e)
      e.resource_type == "AWS::CloudFormation::Stack" and not e.resource_status.match(/IN_PROGRESS/)
    end

    # Calls $stdout.sync.  Returns 0/1/2, like the command line exit code.
    def run
      @stack_id = resolve_stack(@config.stack_name_or_id)

      events = all_events

      if @config.since
        show_events(events_since_time(events, @config.since))
      else
        show_events(events)
      end

      return 0 unless @config.forever or @config.wait

      while @config.forever or not steady_state?(events.last)
        $stdout.sync
        sleep @config.poll_seconds

        new_events = events_since_id(events.last.event_id)

        unless new_events.empty?
          show_events(new_events)
          events = new_events
        end
      end

      return 2 if events.last.resource_status.match /FAILED/
      return 1 if events.last.resource_status.match /ROLLBACK/
      return 0
    end

  end

end
