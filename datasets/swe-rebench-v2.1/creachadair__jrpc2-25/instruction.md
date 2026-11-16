Support server -> client requests
Currently the library supports just server to client notifications via [`jrpc2.ServerPush()`](https://pkg.go.dev/github.com/creachadair/jrpc2?tab=doc#ServerPush).

[The Language Server Protocol spec](https://microsoft.github.io/language-server-protocol/specifications/specification-current/) describes a number of RPC calls which are meant to be sent from the server to the client and responded to - i.e. treated as requests, rather than notifications.

For example:

 - `client/registerCapability`
 - `client/unregisterCapability`
 - `window/showMessageRequest`
 - `window/workDoneProgress/create`
 - `workspace/applyEdit`
 - `workspace/configuration`
 - `workspace/workspaceFolders`

and here are some examples of how it's used:

 - [gopls](https://github.com/golang/tools/blob/99be2d6e796f9bc16b66c42a44c468872fd31f66/internal/lsp/protocol/tsclient.go#L70-L117) (server)
 - [Sublime Text LSP](https://github.com/sublimelsp/LSP/blob/33569cde267ff754cb39467083102aeb94ce65a2/plugin/core/windows.py#L529-L551) (client)

Would there be any interest in adding support for this functionality to the library?

### Additional contract requirements

The library must provide a server-initiated RPC request that the connected client can handle and answer. Expose this operation as `(*Server).Callback(ctx context.Context, method string, params interface{}) (*Response, error)`, and provide the client's response handler through `ClientOptions.OnCallback`, which receives the request and returns a result or error. A successful callback must return the client's actual result in the response; a client error must be returned to the server with the client's error message preserved in the returned error.
