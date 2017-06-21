cfn-events
==========

Watch AWS CloudFormation stack events and wait for completion.

Installation
------------

```
  gem build cfn-events.gemspec
  gem install cfn-events*.gem
```

Use
---

Example usages (all assuming the stack name MyStack):

```
  # Show recent events
  cfn-events MyStack

  # Show recent events, and poll for new events, forever (ctrl-C to end)
  cfn-events --forever MyStack

  # Show recent events, and poll for new events, until the stack reaches a
  # stable state
  cfn-events --wait MyStack
```

More options are available; see `cfn-events --help`.

cfn-events can also be used as a Ruby library.  See `bin/cfn-events` for a
guide for how to do this.

