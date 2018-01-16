lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cfn-events/version'

Gem::Specification.new do |s|
  s.name        = 'cfn-events'
  s.version     = CfnEvents::VERSION
  s.licenses    = [ 'Apache-2.0' ]
  s.date        = '2017-09-11'
  s.summary     = 'Watch AWS CloudFormation stack events and wait for completion'
  s.description = '
    cfn-events reads the events for an AWS CloudFormation stack.  It can
    be used to "tail" the log, and to wait until a stack update is resolved,
    successfully or otherwise.

    Defaults to eu-west-1, or whatever $AWS_REGION is set to.
    Respects $https_proxy.
  '
  s.homepage    = 'https://github.com/rvedotrc/cfn-events'
  s.authors     = ['Rachel Evans']
  s.email       = 'cfn-events-git@rve.org.uk'

  s.executables = %w[
cfn-events
  ]

  s.files       = %w[
lib/cfn-events.rb
lib/cfn-events/client.rb
lib/cfn-events/config.rb
lib/cfn-events/runner.rb
lib/cfn-events/version.rb
  ] + s.executables.map {|s| "bin/"+s}

  s.require_paths = ["lib"]

  s.add_dependency 'aws-sdk', "~> 2.0"
  s.add_development_dependency 'rspec', '~> 3.0'
end
