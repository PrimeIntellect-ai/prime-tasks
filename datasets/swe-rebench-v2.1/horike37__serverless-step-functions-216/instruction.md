Incorrect ServiceEndpoint when there's an API GW function
# This is a Bug Report

## Description

When you have both of these in the same `serverless.yml`:

* an API GW function
* API GW event for a step function

```yml
functions:
  handler:
    handler: functions/handler.handler
    events:
      - http:
          path: /
          method: get

stepFunctions:
  stateMachines:
    apiGatewayTrigger:
      events:
        - http:
            path: /{userId}/{petId}
            method: GET
      definition: ...
```

then `sls deploy` or `sls package` would generate incorrect `ServiceEndpoint`:

```
Service Information
service: step-functions-guide
stage: dev
region: us-east-1
stack: step-functions-guide-dev
resources: 19
api keys:
  None
endpoints:
  GET - https://szp2js5obh.execute-api.us-east-1.amazonaws.com/devamazonaws.com/dev/
functions:
  handler: step-functions-guide-dev-handler
  hello: step-functions-guide-dev-hello
layers:
  None
Serverless StepFunctions OutPuts
endpoints:
  GET - https://szp2js5obh.execute-api.us-east-1.amazonaws.com/devamazonaws.com/dev/{userId}/{petId}
```

Similar or dependent issues:
* #149
* #150

## Additional Data
* ***Serverless Framework Core Version you're using***: 1.42.3
* ***The Plugin Version you're using***: 1.24.0
* ***Operating System***: OSX
* ***Stack Trace***:
* ***Provider Error messages***:

### Additional contract requirements

When both an API Gateway function and a Step Functions API Gateway event are
present, the plugin must leave the generated `ServiceEndpoint` output valid. Its
value must resolve to the API Gateway endpoint
`https://<restApiId>.execute-api.<region>.<urlSuffix>/<stage>` (for example
`https://restApiId.execute-api.us-east-1.amazonaws.com/dev`) and must not
duplicate the host or stage segments. The endpoint may be expressed with any
CloudFormation intrinsic function that resolves to that value (for example
`Fn::Join` or `Fn::Sub`).
