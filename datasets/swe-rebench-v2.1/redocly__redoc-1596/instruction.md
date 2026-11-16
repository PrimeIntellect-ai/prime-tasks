[OAS3] when summary is empty, use $request_type $path
When summary is empty, the generated docs have 'no summary'

Instead, use '$request_type $path' as a summary, eg
GET /users/{username}

Thanks

### Additional contract requirements

- When `summary`, `operationId`, and `description` are all absent, `getOperationSummary` returns the operation's `pathName` (for example `/users/{username}`). The request type (for example `GET`) is not part of the returned string; the `$request_type $path` label shown in the UI is composed by rendering the request type separately from this returned path.
