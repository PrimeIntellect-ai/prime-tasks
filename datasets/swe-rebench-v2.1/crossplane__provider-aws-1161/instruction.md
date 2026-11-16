S3 Bucket NotificationConfiguration Queue referencers should extract ARN instead of external name
### What happened?

The current referencer implementation for `spec.forProvider.noficationConfiguration.queueConfigurations[].queueArn` in `Bucket` does extract the value of the `crossplane.io/external-name` annotation but the field requires the ARN from `status.atProvider.queueArn`.


### How can we reproduce it?

1. Create a queue from `examples`
2. Create a bucket from `examples` with `spec.forProvider.noficationConfiguration` set to the following:
```yaml
        queueArnRef:
          name: test-queue3
```
3. The bucket creation fails because the field does not contain a valid ARN.

### What environment did it happen in?

`provider-aws: v0.24.1`
