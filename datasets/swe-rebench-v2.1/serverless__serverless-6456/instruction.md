Serverless implicitly lowercases object suffix when using existing S3
<!--
1. If you have a question and not a bug report please ask first at http://forum.serverless.com
2. Please check if an issue already exists. This bug may have already been documented
3. Check out and follow our Guidelines: https://github.com/serverless/serverless/blob/master/CONTRIBUTING.md
4. Fill out the whole template so we have a good overview on the issue
5. Do not remove any section of the template. If something is not applicable leave it empty but leave it in the Issue
6. Please follow the template, otherwise we'll have to ask you to update it
-->

# This is a Bug Report

## Description

- What went wrong?

I'm setting an event on an existing S3 bucket, as described in https://serverless.com/framework/docs/providers/aws/events/s3#using-existing-buckets. When setting the event this way, `serverless` implicitly lowercases the object suffix in the event rule. This causes the event not to work when the created object has a suffix that is not lowercase.

- What did you expect should have happened?

Serverless should preserve the casing of the suffix when creating the event rule. For comparison, the [existing-s3](https://www.npmjs.com/package/serverless-plugin-existing-s3) plugin preserves the casing.

- What was the config you used?

```yaml
      - s3:
          bucket: ${opt:s3-bucket}
          events:
            - s3:ObjectCreated:*
          rules:
            - prefix: my-output/
            - suffix: _LATEST
          existing: true
```

Similar or dependent issues:

N/A

## Additional Data

- Serverless version: 1.48.0
- OS: Ubuntu 18.04
