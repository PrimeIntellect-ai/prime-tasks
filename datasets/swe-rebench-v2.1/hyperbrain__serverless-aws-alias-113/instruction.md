Issue when using custom authorizers with serverless-pseudo-parameters plugin
Hi,

I stumbled upon this today:
when using the [serverless-pseudo-parameters](https://www.npmjs.com/package/serverless-pseudo-parameters) plugin, the custom authorizer support breaks.

    An error occurred: AuthorizerApiGatewayAuthorizerdev - Invalid Authorizer URI: :${stageVariables.SERVERLESS_ALIAS}arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:811794430790:function:authorizer/invocations. Authorizer URI should be a valid API Gateway ARN that represents a Lambda function invocation..

Reason seems to be that the pseudo parameters plugin replaces the direct arn reference of the lambda `arn:aws:lambda: ....` with a call to Cloudformation `Fn::Sub` function (as intented). This break the detection of the custom authorizer as I implemented it.

    ...
    {
       "Fn::Sub": "arn:aws:lambda:${AWS::Region}:${AWS::AccountId}:function:authorizer"
    },
    ...

I created a Pull Request to fix this.

### Additional contract requirements

- A custom authorizer is treated as *externally referenced* when its `AuthorizerUri` references a Lambda function ARN either directly (a string starting with `arn:aws:lambda`) or indirectly through `Fn::Sub` (an object whose `Fn::Sub` value starts with `arn:aws:lambda`).
- For an externally referenced custom authorizer the `AuthorizerUri` must remain an external reference to the same Lambda function: the alias stage variable (`${stageVariables.SERVERLESS_ALIAS}`) must not be inserted into it, and the referenced function ARN (including the function name, e.g. `custom-auth`) must be preserved. The exact intrinsic-expression shape of the URI is not prescribed.
- The authorizer resource is renamed to `<LogicalId><alias>` (for example `PseudoParamCustomAuthApiGatewayAuthorizermyAlias`), and any `AuthorizerId` references and `DependsOn` entries that point at the authorizer are updated to the new logical id.
