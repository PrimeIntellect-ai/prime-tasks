Push notifications/requests from outside handlers
In [our language server](https://github.com/hashicorp/terraform-ls) we spin up a few routines as part of compatible `server.Service`

https://github.com/creachadair/jrpc2/blob/446228c04965bd4328cac6e1a43af81198ddf998/server/loop.go#L13-L20

These routines can be long-lived, but never longer than the lifetime of a session - hence we spin them up as part of `Assigner` and stop as part of `Finish`.

In particular we have three things running outside of handlers currently:

 - watcher (watching the filesystem for relevant changes)
 - walker (walking the filesystem on `initalize` to understand relationships between different folders user has in the hierarchy)
 - "module loader" - this is basically a task queue with a worker pool which executes various tasks on the background without blocking any handler response, reflecting that these tasks may take a while to finish and there can be many queued
    - config parsing
    - obtaining version of Terraform
    - parsing metadata relevant to open files/folders

This all works aok, but we'd also like to report progress on some of these operations, i.e. send `$/progress` notifications back to the client.

I think the best way of solving that might be introduction of a new function which can extract the `*Server` out of the context as part of a handler. This then allows for it to be persisted somewhere outside of the short-lived handler context.

```go
[HIDDEN]
```
alternatively instead of exposing the whole `*Server` the function could extract an interface such as this one
```go
type ServerPusher interface {
  Callback(ctx context.Context, method string, params interface{}) (*Response, error)
  Notify(ctx context.Context, method string, params interface{}) error
}
```
just to discourage from using other parts of the API in that context. Obviously the interface can easily be just casted back to `*Server`, but it would still communicate the intentions better?

---

I would be happy to send a PR - let me know what you think.

### Additional contract requirements

Expose the accessor as `jrpc2.ServerFromContext`. A request handler must be able to obtain a push-capable handle associated with the server that invoked it. The handler may retain the handle after returning and use it with an appropriate context to send notifications and callback requests to the same client.
