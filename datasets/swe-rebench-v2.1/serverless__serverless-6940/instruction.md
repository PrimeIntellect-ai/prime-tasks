ALB multi value headers support
# This is a Feature Proposal

## Description

ALB target groups support a `Multi value headers` configuration which allows you to pass through multiple headers and query parameters as a list. It would be great if this could be configured from serverless.yml.

### Additional contract requirements

- ALB events accept a boolean `multiValueHeaders` option in `serverless.yml`. When it is `true`, the generated target group enables multi-value headers; when it is omitted or `false`, multi-value headers are disabled.
- The generated target group resource includes a `TargetGroupAttributes` entry with `Key` `lambda.multi_value_headers.enabled` and `Value` equal to the configured boolean, i.e. `false` when the option is omitted or disabled.
- Add a public method `getAlbTargetGroupLogicalId(functionName, albId, multiValueHeaders)` to the AWS naming module (`lib/plugins/aws/lib/naming.js`). It returns `<NormalizedFunctionName>Alb[MultiValue]TargetGroup<albId>`, where the `MultiValue` segment is present only when `multiValueHeaders` is `true`.
- Add a public method `getAlbTargetGroupNameTagValue(functionName, albId, multiValueHeaders)` to the AWS naming module (`lib/plugins/aws/lib/naming.js`). It returns `<service>-<functionName>-<albId>-[multi-value-]<stage>`, where the `multi-value-` segment is present only when `multiValueHeaders` is `true`.
- Add a public method `getAlbTargetGroupName(functionName, albId, multiValueHeaders)` to the AWS naming module (`lib/plugins/aws/lib/naming.js`). It returns the MD5 hash (a 32-character hexadecimal string) of the value returned by `getAlbTargetGroupNameTagValue` for the same arguments.
- Add a public method `validateMultiValueHeadersAttribute(event, functionName)` to the ALB event validation module (`lib/plugins/aws/package/compile/events/alb/lib/validate.js`). It returns the boolean value of `event.alb.multiValueHeaders` when present and `undefined` when absent. When the attribute is present but not a boolean, it throws a `ServerlessError` whose message contains `Invalid ALB event "multiValueHeaders" attribute`.
