[v2] - Error when using AMAZON_COGNITO_USER_POOLS as additionalAuthentications type
In my serverless.yml I have:

```
  authentication:
    type: AWS_IAM
  additionalAuthentications:
    - type: 'AMAZON_COGNITO_USER_POOLS'
      config:
        userPoolId: xxxx
```

Upon deploy this results in the error:

```
UPDATE_FAILED: GraphQlApi (AWS::AppSync::GraphQLApi)
Property validation failure: [Encountered unsupported properties in {/AdditionalAuthenticationProviders/0/UserPoolConfig}: [DefaultAction]]
```

Problem appears to be that DefaultAction is always set here, when it's only valid for authentication not additionalAuthentications

https://github.com/sid88in/serverless-appsync-plugin/blob/ded433996b31119d9a3bc17fb3a83a1ab5473aae/src/resources/Api.ts#L421
