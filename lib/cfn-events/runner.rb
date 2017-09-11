require 'json'

module CfnEvents

  class Runner

    def initialize(config)
      @config = config

      @config.cfn_client ||= begin
                               effective_options = CfnEvents::Client.core_v2_options.merge(config.client_options)
                               Aws::CloudFormation::Client.new(effective_options)
                             end
    end

    def resolve_stack(stack_name_or_id)
      ans = @config.cfn_client.describe_stacks(stack_name: stack_name_or_id).stacks[0].stack_id
      if ans != stack_name_or_id
        $stderr.puts "Resolved #{stack_name_or_id} to #{ans}"
      end
      ans
    end

    def all_events_so_far
      r = @config.cfn_client.describe_stack_events(stack_name: @stack_id)
      events = r.each_page.flat_map {|page| page.stack_events}.reverse

      if events.empty?
        raise "Stack has no events! Please raise this as a cfn-events bug."
      end

      [ events, events.last ]
    end

    def events_since_time(t)
      r = @config.cfn_client.describe_stack_events(stack_name: @stack_id)

      # If there are no events since the given time, show none, and return the
      # most recent event.  Sort of an edge case.
      if r.stack_events.first.timestamp <= t
        return [ [], r.stack_events.first ]
      end

      events = []
      loop do
        cutoff = r.stack_events.index {|event| event.timestamp <= t}
        if cutoff
          # We can stop looking
          events.concat r.stack_events[0..cutoff-1]
          events.reverse!
          return [ events, events.last ]
        end

        events.concat r.stack_events
        r.next_page? or break
        r = r.next_page
      end

      # ALL the available events are since the given time
      events.reverse!
      return [ events, events.last ]
    end

    def events_since_event(since_event)
      r = @config.cfn_client.describe_stack_events(stack_name: @stack_id)

      # Sort of a special case: no new events
      if r.stack_events.first.event_id == since_event.event_id
        return [ [], since_event ]
      end

      events = []
      r.each_page do |page|
        cutoff = page.stack_events.index {|e| e.event_id == since_event.event_id}

        if cutoff
          events.concat page.stack_events[0..cutoff-1]
          return [ events.reverse, events.first ]
        end

        events.concat r.stack_events
      end

      # Unable to join what we've seen so far to what we can see now
      $stderr.puts "Last-seen stack event is no longer returned by AWS. Please raise this as a cfn-events bug."

      return [ events.reverse, events.first ]
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

      # An assumption to make the logic easier:
      # - there can never be zero events

      # (The closest we seem to get to this is if a stack is created via a
      # change set, then the stack entity is created with a single event,
      # "AWS::CloudFormation::Stack <the stack name> REVIEW_IN_PROGRESS").

      # Therefore there is always a most_recent_event.

      events_to_show, most_recent_event = if @config.since
                                            events_since_time @config.since
                                          else
                                            all_events_so_far
                                          end
      show_events events_to_show

      return 0 unless @config.forever or @config.wait

      while @config.forever or not steady_state?(most_recent_event)
        $stdout.sync
        sleep @config.poll_seconds
        events_to_show, most_recent_event = events_since_event most_recent_event
        show_events events_to_show
      end

      return 2 if most_recent_event.resource_status.match /FAILED/
      return 1 if most_recent_event.resource_status.match /ROLLBACK/
      return 0
    end

  end

end
