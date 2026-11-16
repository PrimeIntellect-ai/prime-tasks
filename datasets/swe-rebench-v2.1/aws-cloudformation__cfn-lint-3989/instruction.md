New rule for mixing/matching API Gateway resource types
### Is this feature request related to a new rule or cfn-lint capabilities?

rules

### Describe the feature you'd like to request

When using `AWS::ApiGateway::RestApi/Body` with `AWS::ApiGateway::Method`, `AWS::ApiGateway::Resource` and maybe more will result in drift detection and unintended results when doing updates.

### Describe the solution you'd like

New warning when using Body/BodyS3Location with `AWS::ApiGateway::Method`, `AWS::ApiGateway::Resource` (and others) will result in a warning.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [x] 👋 I may be able to implement this feature request

### Would this feature include a breaking change?

- [x] ⚠️ This feature might incur a breaking change

### Additional contract requirements

When an `AWS::ApiGateway::RestApi` uses `Body` or `BodyS3Location`, emit a warning if API Gateway `Method`, `Model`, `Resource`, `GatewayResponse`, `RequestValidator`, or `Authorizer` resources reference that RestApi. A RestApi definition without one of these related resource types should not produce this warning.
