http: invalid Read on closed Body error comes in AuthenticationFunc with request body validation
I have a POST request with the request body parameter. I am using `OapiRequestValidatorWithOptions` to validate and authenticate each and every request. However, it gave `http: invalid Read on closed Body` error and fails to bind the JSON to the request object.

I was able to avoid the error by setting ExcludeRequestBody so ValidateRequest skips request body validation as shown in the example below.

```
validator := middleware.OapiRequestValidatorWithOptions(swagger,
		&middleware.Options{
			Options: openapi3filter.Options{
				ExcludeRequestBody: true,
				AuthenticationFunc: NewAuthenticator(middleware.AuthConfig{}),
			},
		})
```
However, I would like to continue to use ValidateRequest.
Is there any solution to this?
