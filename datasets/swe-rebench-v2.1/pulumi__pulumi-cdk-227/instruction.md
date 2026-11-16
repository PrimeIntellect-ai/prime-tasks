LoadBalancer "name" cannot be longer than 32 characters
Question from Community Slack:

> I have a question about names and length of names. When set up an sample infrastructure with Pulumi CDK I got this error message when running pulumi preview:
>
> ```
> Diagnostics:
>   aws:lb:LoadBalancer (loadbalancedserviceLB1BE8EDCE):
>     error: aws:lb/loadBalancer:LoadBalancer resource 'loadbalancedserviceLB1BE8EDCE' has a problem: "name" cannot be longer than 32 characters: "loadbalancedserviceLB1BE8EDCE-403d9b7". Examine values at 'LoadBalancer.Name'.
> ```
>
> The corresponding code looks like this:
>
> ```ts
> const lbservice = new ApplicationLoadBalancedFargateService(this, 'loadbalanced-service', {
>   cluster,
>   taskDefinition: taskdef,
>   desiredCount: 2,
>   serviceName: 'my-service',
>   circuitBreaker: { rollback: true },
>   publicLoadBalancer: true,
>   listenerPort: webserverPort,
> });
> ```
>
> The name part is not an issue with regular AWS CDK, and Pulumi generates a different (shorter) name than AWS CDK, but still too short compared to name lengths allowed by CloudFormation, it seems. The question is really what to think and consider in terms of name issues here, what would be preferred approaches besides keeping construct id values short - and how many levels will this work out with?


I suspect that the issue is that we should be passing name through explicitly in the mapping linked below if provided (which it will always be I believe?) so that Pulumi doesn't apply it's own autonaming here.  If you open an issue on this - we can look into whether that is indeed the right resolution.
https://github.com/pulumi/pulumi-cdk/blob/342f7d5bbbc0d272c7e1616ae108b04c478add5d/src/aws-resource-mappings.ts#L210
Long logical ID (>100 characeters) breaks AWS::Lambda::Permission
### What happened?

My CDK stack creates an AWS::Lambda::Permission resource with a long logical ID:

StockBotApiGatewayGETeventualexecutionsexecutionIdhistoryexecutionseventsintegrationPermission3C1EE9F9

This then results in an error:

```
  aws:lambda:Permission (StockBotApiGatewayGETeventualexecutionsexecutionIdhistoryexecutionseventsintegrationPermission3C1EE9F9):
    error: aws:lambda/permission:Permission resource 'StockBotApiGatewayGETeventualexecutionsexecutionIdhistoryexecutionseventsintegrationPermission3C1EE9F9' has a problem: expected length of statement_id to be in the range (1 - 100), got StockBotApiGatewayGETeventualexecutionsexecutionIdhistoryexecutionseventsintegrationPermission3C1EE9F9. Examine values at 'Permission.StatementId'.
```

### Expected Behavior

Pulumi should probably truncate the name to avoid this problem.

### Steps to reproduce

I'm not 100% sure where my code is creating this. I believe it's for when I configure an API GW v2 to trigger my Lambda:

```ts
import { HttpApi } from "@aws-cdk/aws-apigatewayv2-alpha";
import { HttpIamAuthorizer } from "@aws-cdk/aws-apigatewayv2-authorizers-alpha";
import { HttpLambdaIntegration } from "@aws-cdk/aws-apigatewayv2-integrations-alpha";

const handler= new aws_lambda.Function(this, "F", { .. });

new HttpApi(this, "Gateway", {
  apiName: `my-api`,
  defaultIntegration: new HttpLambdaIntegration("default", handler),
});
```

### Output of `pulumi about`

```
CLI
Version      3.53.1
Go Version   go1.19.5
Go Compiler  gc

Plugins
NAME    VERSION
aws     5.28.0
nodejs  unknown

Host
OS       darwin
Version  13.1
Arch     arm64

This project is written in nodejs: executable='/Users/samgoodwin/.nvm/versions/node/v16.14.2/bin/node' version='v16.14.2'

Current Stack: sam-g/stock-bot/stock-bot

TYPE                 URN
pulumi:pulumi:Stack  urn:pulumi:stock-bot::stock-bot::pulumi:pulumi:Stack::stock-bot-stock-bot


Found no pending operations associated with stock-bot

Backend
Name           pulumi.com
URL            https://app.pulumi.com/sam-g
User           sam-g
Organizations  sam-g
```

### Additional context

_No response_

### Contributing

Vote on this issue by adding a 👍 reaction.
To contribute a fix for this issue, leave a comment (and link to your pull request, if you've opened one already).

### Additional contract requirements

- When the application is created without an `aws-native` provider, it creates a default `aws-native` provider named `cdk-aws-native` and applies it to the resources generated from the CDK app. The provider is configured with the AWS region from the `AWS_REGION` environment variable, with `autoNaming.autoTrim` enabled, and with `autoNaming.randomSuffixMinLength` set to `7`. This makes generated names that exceed a service limit be trimmed to fit.
- When an `aws-native` provider is supplied through the `providers` option (either as a list of providers or as a map keyed by package name), no additional default `aws-native` provider is created.
- Add an exported async function `testApp(fn: (scope: Construct) => void, options?: pulumi.ComponentResourceOptions)` in the module `tests/mocks.ts`. It builds a `TestStack`, runs `fn` within a synthetic CDK app, and forwards `options` to the `App` constructor. It resolves after the converter processes the stack and all resources have been collected.
