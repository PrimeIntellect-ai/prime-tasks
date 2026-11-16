Cannot read property 'Fn::Join' of undefined when specifying a User Pools authorizer
Attempting to deploy  i get error ` Cannot read property 'Fn::Join' of undefined`, this is the logs terminals.

> Serverless: Packaging service...
> Serverless: Preparing alias ...
>
>   Type Error ---------------------------------------------
>
>      Cannot read property 'Fn::Join' of undefined
>
>      For debugging logs, run again after setting the "SLS_DEBUG=*" environment variable.
>
>   Get Support --------------------------------------------
>      Docs:          docs.serverless.com
>      Bugs:          github.com/serverless/serverless/issues
>      Forums:        forum.serverless.com
>      Chat:          gitter.im/serverless/serverless
>
>   Your Environment Information -----------------------------
>      OS:                 darwin
>      Node Version:       6.9.1
>      Serverless Version: 1.14.0

can you help me, thanks?

### Additional contract requirements

- For API-Gateway authorizer resources of type `TOKEN`, the `${stageVariables.SERVERLESS_ALIAS}` stage variable is injected into the Lambda-authorizer URI and the alias suffix is appended to the authorizer's logical name.
- References and dependencies that point to a renamed authorizer are updated to the new logical name.
