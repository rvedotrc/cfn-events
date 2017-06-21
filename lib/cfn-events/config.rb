module CfnEvents

  class Config
    # Stronger builder pattern would be nice
    attr_accessor :client_options, :cfn_client,
      :stack_name_or_id,
      :output_json,
      :since, :wait, :forever, :poll_seconds

    def initialize
      @client_options = {}
      @since = nil
      @output_json = false
      @wait = false
      @forever = false
      @poll_seconds = 5
    end

    def build
      if !@stack_name_or_id
        raise "Missing stack_name_or_id"
      end

      if @wait and @forever
        raise "wait and forever cannot be combined"
      end

      self
    end
  end

end
