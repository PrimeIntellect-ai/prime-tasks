Allow namespace to be specifiable via environment variables
See also: https://github.com/awslabs/aws-embedded-metrics-python/issues/15

### Additional contract requirements

The namespace recorded in emitted metrics can be overridden with the `AWS_EMF_NAMESPACE` environment variable. When that variable is not set, emitted metrics continue to use the existing default namespace, `aws-embedded-metrics`.
