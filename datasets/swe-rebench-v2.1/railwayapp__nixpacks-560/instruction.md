Add RAILS_LOG_TO_STDOUT=enabled by default to RoR projects
### Feature request

Some Ruby projects doesn't send application logs to stdout once started.
`RAILS_LOG_TO_STDOUT=enabled ` should fix the issue

It would be better to have it as the default behavior!

### Motivation

_No response_

### Contribution

_No response_

### Additional contract requirements

- For a Ruby on Rails project, the generated build plan's `variables` map must contain `RAILS_LOG_TO_STDOUT` with the value `enabled`, next to the Ruby variables (such as `GEM_HOME` and `BUNDLE_GEMFILE`) that the Ruby provider already places there.
