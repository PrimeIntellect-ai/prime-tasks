Support sequential request processing or selective request ordering
Asynchronous processing of requests is useful from performance perspective. Unfortunately there are scenarios in LSP where ordering matters.

One example is when the client sends a number of partial text edits which need to be applied in that particular order.

As per LSP it is necessary to process any `textDocument/didChange` requests in the same order they were received:

https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_didChange

```ts
        /*
	 * To mirror the content of a document using change events use the following approach:
	 * - start with the same initial content
	 * - apply the 'textDocument/didChange' notifications in the order you receive them.
	 * - apply the `TextDocumentContentChangeEvent`s in a single notification in the order
	 *   you receive them.
	 */
```

In theory the incoming requests could be ordered by IDs, but:

1. IDs are not even guaranteed to be numbers in LSP and even when they are the numbers may not have any meaning
2. Even though clients seem to be sending IDs in `textDocument/didChange` requests, the LSP technically documents this as a notification method - i.e. request should not contain ID and should not be responded to

In some cases it may be possible to order requests by version ID, but the sequence may not be complete, so there is no point in queuing the requests and waiting if a particular version arrives.

https://microsoft.github.io/language-server-protocol/specifications/specification-current/#versionedTextDocumentIdentifier

> The version number of a document will increase after each change, including
> undo/redo. The number doesn't need to be consecutive.

---

`gopls` (Go language server) seems to be implementing purely sequential server, which I don't is strictly necessary, but it probably reduces the complexity quite a bit which may be preferable. i.e. It is IMO sensible to temporarily compromise the performance in favour of getting the overall implementation right.

Lastly the LSP spec says the following about ordering:

> **Request, Notification and Response ordering**
>
> Responses to requests should be sent in roughly the same order as the requests appear on the server or client side. So for example if a server receives a textDocument/completion request and then a textDocument/signatureHelp request it will usually first return the response for the textDocument/completion and then the response for textDocument/signatureHelp.
>
> However, the server may decide to use a parallel execution strategy and may wish to return responses in a different order than the requests were received. The server may do so as long as this reordering doesn’t affect the correctness of the responses. For example, reordering the result of textDocument/completion and textDocument/signatureHelp is allowed, as these each of these requests usually won’t affect the output of the other. On the other hand, the server most likely should not reorder textDocument/definition and textDocument/rename requests, since the executing the latter may affect the result of the former.
