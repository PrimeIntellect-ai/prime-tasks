Setting Oauth scope in Api Gateway does not work for step functions
 have a step function with http event configured. I am using Cognito authorizer and using oauth scopes. Syntax is the same as with Lambda and API Gateway configuration (which works correctly).

Example of cfg:

```yaml
stepFunctions:
  stateMachines:
    calculate:
            events:
            - http:
                path: v1/calculate
                method: POST
                cors: true
                authorizer:
                  name: authorizer
                  arn: 'arn'
                  identitySouce: method.request.header.Authorization
                  scopes:
                    - 'scope1'
```

## Additional Data

* ***Serverless Framework Version you're using***:   1.42.3
* ***Provider Error messages***:  deployment works well, authorizer is set but scope is not set
* ***Provider Error messages***:

### Additional contract requirements

- For a step-function HTTP event using a Cognito authorizer, propagate configured OAuth scopes to the API Gateway method’s `AuthorizationScopes` property.
