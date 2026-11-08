If `MultiError` is enabled via `chi_middleware.OapiRequestValidatorWithOptions()`, the sever always return 500 as status code about invalid request.
I'm using `chi` with `github.com/deepmap/oapi-codegen/pkg/chi-middleware` to validate the request body.
But if `MultiError` is enabled looks like below, it always return 500 as status code when the request is invalid. I expect it returns 400.
```go
	r := chi.NewRouter()
	r.Use(
		middleware.RequestID,
		middleware.Recoverer,
		chi_middleware.OapiRequestValidatorWithOptions(swagger, &chi_middleware.Options{
			Options: openapi3filter.Options{
				MultiError: true,
			},
		}),
	)
```

[HIDDEN]
[HIDDEN]
```go
	if err := openapi3filter.ValidateRequest(context.Background(), requestValidationInput); err != nil {
		[HIDDEN]
		[HIDDEN]
			// We've got a bad request
			// Split up the verbose error by lines and return the first one
			// openapi errors seem to be multi-line with a decent message on the first
			errorLines := strings.Split(e.Error(), "\n")
			return http.StatusBadRequest, fmt.Errorf(errorLines[0])
		[HIDDEN]
			return http.StatusUnauthorized, err
		[HIDDEN]
			// This should never happen today, but if our upstream code changes,
			// we don't want to crash the server, so handle the unexpected error.
			[HIDDEN]
		}
	}
```

So, it always return `http.StatusInternalServerError`.

## Environment

- `opai-codegen`: v1.8.2
- Go: 1.17

### Additional contract requirements

The chi middleware in `pkg/chi-middleware` must expose a `MultiErrorHandler` option on `Options` with the signature `func(openapi3.MultiError) (int, error)`. When request validation produces an `openapi3.MultiError`, this handler is called with the aggregated error, and the status code and error it returns are used for the response. When no handler is set, the middleware responds with HTTP 400 and the aggregated error.

The gin middleware in `pkg/gin-middleware` must expose a `MultiErrorHandler` option on `Options` with the signature `func(openapi3.MultiError) error`. When request validation produces an `openapi3.MultiError`, this handler is called with the aggregated error, and the error it returns is used for the response. When no handler is set, the middleware responds with HTTP 400 and an error message that contains `multiple errors encountered`.

The echo middleware in `pkg/middleware` must expose a `MultiErrorHandler` option on `Options` with the signature `func(openapi3.MultiError) *echo.HTTPError`. When request validation produces an `openapi3.MultiError`, this handler is called with the aggregated error, and the `*echo.HTTPError` it returns is used for the response. When no handler is set, the middleware responds with HTTP 400 and the aggregated error message.

The aggregated error message must contain the underlying validation details: the offending query parameter names (`parameter "id"` and `parameter "id2"`; in the Gin and Echo responses these appear JSON-escaped as `parameter \"id\"` and `parameter \"id2\"`), `value is required but missing` for a missing required value, `number must be at most 100` or `number must be at least 10` for an out-of-range value, and `parsing "abc": invalid syntax` for an invalid integer.
