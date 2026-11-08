[oauth2] authorization server must throw invalid request exception if request includes a parameter more than once
```
invalid_request
               The request is missing a required parameter, includes an
               invalid parameter value, includes a parameter more than
               once, or is otherwise malformed.
```

### Additional contract requirements

- For an authorization request that includes `response_type` more than once, the redirect location must be exactly `/test/oauth/error?error=invalid_request&error_description=Parameter+%255Bresponse_type%255D+is+included+more+than+once`.
