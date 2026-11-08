Feature: add support for STS Session Tags when assuming roles
Our company is using aws-vault in our devops workflows and we would like to implement an ABAC authorisation strategy against some resources.

It would be great if aws-vault supported IAM Session Tags [when `AssumeRole()` is used](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html#id_session-tags_adding-assume-role).

Ideally, the session and transitive tags should be set up separately for each role in the chain  using `~/.aws/config` profile parameters as well as environment variables.

### Additional contract requirements

- The `~/.aws/config` profile parameters are named `session_tags` (a comma-separated list of `key=value` pairs) and `transitive_session_tags` (a comma-separated list of tag keys).
- The environment variables are named `AWS_SESSION_TAGS` (a comma-separated list of `key=value` pairs) and `AWS_TRANSITIVE_TAGS` (a comma-separated list of tag keys).
- When `AssumeRole()` is used, the configured session tags are sent as the `Tags` of the STS `AssumeRole` request and the configured transitive tag keys are sent as the `TransitiveTagKeys` of that request.
