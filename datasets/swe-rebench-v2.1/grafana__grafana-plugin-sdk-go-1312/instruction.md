Stop using http.DefaultClient
When `httpclient.New()` is called without providing any options we [return http.DefaultClient](https://github.com/grafana/grafana-plugin-sdk-go/blob/ef2d80624da9a8e9e09e50791ae4f7f7b0f48c01/backend/httpclient/http_client.go#L25), which can lead to unexpected behavior and create potential security issues if it has been modified by another caller.

It also means that `httpclient.New()` and `httpclient.New(httpclient.Options{})` have different semantics as the latter (correctly) returns a new `http.Client` with all of our default settings, middleware, etc. This is confusing by itself, but is even more confusing to a user who attempts to pass (or stop passing) a single option and gets a completely different set of client behaviors.

[HIDDEN]

It's possible that this change will cause problems for callers who are either relying on side effects of changes to `http.DefaultClient`, or are not expecting our default settings or middleware.

In both of these cases the caller has the option of replacing `httpclient.New()` with `http.DefaultClient` (or `&http.Client{}`) if they want the default client rather than our opinionated client.

### Additional contract requirements

- Calling `httpclient.New()` without options must return a client other than the shared `http.DefaultClient`, with the same SDK default configuration and middleware semantics as `httpclient.New(httpclient.Options{})`.
