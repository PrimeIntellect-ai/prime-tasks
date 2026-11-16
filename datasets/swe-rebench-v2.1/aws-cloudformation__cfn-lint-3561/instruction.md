[feature request] Validate Cloudfront::Distribution.DistributionConfig.DefaultCacheBehavior.TargetOriginId exists
*cfn-lint version: v0.60.1*

*Description of issue.*

The linter seems like it should validate that `TargetOriginId` must be set to an origin that exists in `DistributionConfig.Origins` array (please let me know and close if I'm incorrect). We're using AWS SAM to deploy the cloudformation template.

Currently this error is only caught (with a generic error message) at the time that cloudformation is deployed via `sam deploy`.
It would be great if this could be caught in static analysis - especially considering how updating cloudfront distributions via cloudformation is slow.

Example:
```yml
Resources:
  ReverseProxyCloudfrontDistribution:
    Type: 'AWS::CloudFront::Distribution'
    DependsOn:
      - ReactProjectCloudfrontDistribution
    Properties:
      DistributionConfig:
        Enabled: true
        Comment: 'My Website Reverse Proxy'
        HttpVersion: http2
        Origins:
          - Id: proxy-to-react-project
            DomainName: !GetAtt ReactProjectCloudfrontDistribution.DomainName
            CustomOriginConfig:
              OriginProtocolPolicy: "https-only"
          - Id: proxy-to-backend-orm
            DomainName: 'staging.mywebsite.com'
            CustomOriginConfig:
              OriginProtocolPolicy: "https-only"
        DefaultCacheBehavior:
          Compress: 'true'
          AllowedMethods:
            - GET
            - HEAD
            - OPTIONS
          ForwardedValues:
            QueryString: true
          #
          # !!!!!!!!!! SEE HERE !!!!!!!!!!
          # I made a (rather obvious) typo to show that the linter does not catch this
          # it should be set to `proxy-to-react-project`
          #
          TargetOriginId: proxy-to-REACTTTTTTT-project
          ViewerProtocolPolicy : allow-all

  ReactProjectCloudfrontDistribution:
    Type: 'AWS::CloudFront::Distribution'
    Properties:
      # omitted for this example
      # not relevent to the issue being discussed
```

Error message when deploying:
```
"Invalid request
provided: One or more of
your origins or origin
groups do not exist.
(Service: CloudFront, Status
Code: 404, Request ID: 47dd8
910-c4e0-4c2c-9b55-6df586af6
56e)" (RequestToken: 57323dc
4-fb71-c4be-c472-e738ec6d3de
4, HandlerErrorCode:
InvalidRequest)
```

### Additional contract requirements

- Add a public rule class `DistributionTargetOriginId` in module
  `cfnlint.rules.resources.cloudfront.DistributionTargetOriginId`. It must be
  constructible with no arguments.
- The rule exposes a `validate(self, validator, _, instance, schema)` method that
  returns an iterable of validation errors.
- When `DefaultCacheBehavior.TargetOriginId` is a string that does not match any
  string `Origins[*].Id` in the same `DistributionConfig`, the rule reports a
  `ValidationError` whose validator is `enum` and whose message is exactly
  `'<target>' is not one of [<ids>]`. For example, when `TargetOriginId` is
  `origin-id` and the available string origin IDs are `foo` and `bar`, the message
  must be exactly `'origin-id' is not one of ['foo', 'bar']`.
