access source ip address
I was hoping to be able to pass the source IP along to the script, but i couldn't find a way to access it through the [request-values](https://github.com/adnanh/webhook/blob/master/docs/Referencing-Request-Values.md) section
Am I missing something? Or is my only real option to parse the stdout of webhook and attempt to grab the last line with "incoming HTTP request from" (if that would even work...)

any pointers would be greatly appreciated!

### Additional contract requirements

- Add a request-value source named `request` to the `Argument.Get(r *Request) (string, error)` method in package `internal/hook`. It supports the name `remote-addr`, which returns the client's remote address.
- The `Request` struct in package `internal/hook` exposes the original HTTP request through a public field `RawRequest *http.Request`.
- `Argument.Get` returns an error when the request is nil, when the `RawRequest` field is missing, or when the supplied name is not one of the supported request keys.
