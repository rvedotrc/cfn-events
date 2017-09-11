require 'cfn-events'
require 'ostruct'
require 'time'

describe CfnEvents::Runner do

  STACK_NAME = 'MyStack'
  STACK_ID = 'some-stack-id'

  before do
    @seq = 0
    @timestamp = Time.parse('2017-08-05 12:51:44') # no reason
    @cfn_client = double('AWS::CloudFormation::Client')
    expect(@cfn_client).to receive(:describe_stacks).with(stack_name: STACK_NAME).and_return(
      OpenStruct.new(stacks: [ OpenStruct.new(stack_id: STACK_ID) ])
    )
  end

  def an_event(fields = {})
    @seq = @seq + 1
    @timestamp = @timestamp + 1

    OpenStruct.new({
      event_id: "event-%06d" % @seq,
      timestamp: @timestamp,
      resource_type: 't',
      resource_status: 's',
      logical_resource_id: 'x',
      physical_resource_id: 'o',
      resource_status_reason: 'r',
    }.merge fields)
  end

  def a_stack_event(status)
    an_event(resource_type: 'AWS::CloudFormation::Stack', resource_status: status)
  end

  def page_of_events(events, next_page = nil)
    response = OpenStruct.new(stack_events: events, next_page: next_page)

    def response.each_page
      return enum_for(:each_page) unless block_given?
      yield self
      if next_page
        next_page.each_page {|page| yield page}
      end
    end

    def response.next_page?
      next_page != nil
    end

    response
  end

  def expect_json_events(events, runner)
    outputted_events = []
    allow(runner).to receive(:puts) do |s|
      outputted_events << JSON.parse(s)
    end

    r = yield

    expect(outputted_events.count).to eq(events.count)
    outputted_events.zip(events).each do |actual, expected|
      expect(actual["event_id"]).to eq(expected.event_id)
    end

    r
  end

  it "handles one-off single page" do
    events = 5.times.map { an_event }
    page = page_of_events(events.reverse)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles one-off multiple pages" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events0+events1+events2, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles one-off multiple pages with 'since' discarding some events" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.since = events0[2].timestamp
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events0[3..-1]+events1+events2, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles one-off multiple pages with 'since' discarding no events" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.since = events0.first.timestamp - 100
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events0+events1+events2, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles one-off multiple pages with 'since' discarding all events" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.since = events2.last.timestamp
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events([], runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles wait-mode without polling" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    events2 << a_stack_event('CREATE_COMPLETE')
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.wait = true
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events0+events1+events2, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles wait-mode with polling" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    events3 = events2[-3..-1] + [ an_event, an_event ]
    events4 = 5.times.map { an_event } + [ a_stack_event('CREATE_COMPLETE') ]
    page3 = page_of_events(events3.reverse)
    page4 = page_of_events(events4.reverse, page3)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2, page4)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.wait = true
    config.poll_seconds = 1
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events0+events1+events2+events3[-2..-1]+events4, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

  it "handles wait-mode with polling and no overlap" do
    events0 = 5.times.map { an_event }
    events1 = 5.times.map { an_event }
    events2 = 5.times.map { an_event }
    page0 = page_of_events(events0.reverse)
    page1 = page_of_events(events1.reverse, page0)
    page2 = page_of_events(events2.reverse, page1)

    events4 = 5.times.map { an_event } + [ a_stack_event('CREATE_COMPLETE') ]
    page4 = page_of_events(events4.reverse)

    expect(@cfn_client).to receive(:describe_stack_events).with(stack_name: STACK_ID).and_return(page2, page4)

    config = CfnEvents::Config.new
    config.output_json = true
    config.stack_name_or_id = STACK_NAME
    config.wait = true
    config.poll_seconds = 1
    config.cfn_client = @cfn_client

    runner = CfnEvents::Runner.new(config)

    r = expect_json_events(events0+events1+events2+events4, runner) do
      runner.run
    end

    expect(r).to eq(0)
  end

end
