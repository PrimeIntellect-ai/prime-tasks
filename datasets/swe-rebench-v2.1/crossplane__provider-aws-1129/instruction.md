S3 replication metrics requires eventThreshold
### What happened?
When trying to configure an S3 bucket with the following replication spec, we encounter an error from the AWS API.

```yaml
replicationConfiguration:
  role: arn:aws:iam::<redacted>:role/<redacted>
  rules:
  - status: Enabled
     destination:
       bucket: arn:aws:s3:::<redacted>
       account: "<redacted>"
       replicationTime:
         status: Disabled
         time:
           minutes: 15
       accessControlTranslation:
         ownerOverride: Destination
       metrics:
         status: Enabled
         eventThreshold:
           minutes: 15
```

As far as I understand it, enabling `metrics`, with `replicationTime` disabled is valid configuration, the above configuration gives us the following error:

`cannot create or update: api error InvalidArgument: Metrics cannot contain an event threshold when ReplicationTime is not specified or Disabled`

However, `metrics.eventThreshold` cannot be omitted since this is a field required by the provider.

### What environment did it happen in?
Crossplane version: `v1.6.1`
Provider version: `v0.23.0`

### Additional contract requirements

- A replication metrics configuration is valid without `eventThreshold`; the provider's resource schema must accept that omission.
- When `eventThreshold` is omitted, the provider must safely handle the configuration and leave the threshold absent from the AWS replication request, including when metrics are enabled and replication time is disabled.
- When AWS reports replication metrics without `eventThreshold`, late initialization must complete without error and keep the threshold absent.
