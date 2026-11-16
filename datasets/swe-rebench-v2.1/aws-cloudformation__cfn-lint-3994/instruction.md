S3 Bucket Tier Configuration: `Days specified in ARCHIVE_ACCESS tier should not be less than 90`
### CloudFormation Lint Version

cfn-lint 1.27.0

### What operating system are you using?

Mac

### Describe the bug

Cfnlint should notify users if they have an improper config for S3 bucket tiering configuration. For example, a configuration with the following yields an error when deployed: `Days specified in ARCHIVE_ACCESS tier should not be less than 90.`

```yaml
MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      IntelligentTieringConfigurations:
        - Id: ColdIntelligentTieringConfig
          Status: Enabled
          Tierings:
            - AccessTier: ARCHIVE_ACCESS
              Days: 1
            - AccessTier: DEEP_ARCHIVE_ACCESS
              Days: 7
```

### Expected behavior

Cfnlint raises an error when any s3 bucket tier configuration is incorrect.

### Reproduction template

```yaml
MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      IntelligentTieringConfigurations:
        - Id: ColdIntelligentTieringConfig
          Status: Enabled
          Tierings:
            - AccessTier: ARCHIVE_ACCESS
              Days: 1
            - AccessTier: DEEP_ARCHIVE_ACCESS
              Days: 7
```

### Additional contract requirements

- Add a rule class `BucketTieringConfiguration` in module `cfnlint.rules.resources.s3.BucketTieringConfiguration` with rule id `E3061`.
- The rule exposes a method `validate(self, validator, _, instance, schema)` that yields the validation errors for a single tiering configuration.
- The rule is applied to each entry of `Tierings` under `IntelligentTieringConfigurations` on `AWS::S3::Bucket` resources.
- For `AccessTier` `ARCHIVE_ACCESS`, `Days` must be between 90 and 730 inclusive.
- For `AccessTier` `DEEP_ARCHIVE_ACCESS`, `Days` must be between 180 and 730 inclusive.
