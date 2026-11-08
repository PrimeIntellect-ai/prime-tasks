Add support for ensureParentId API
For example [docs for .NET agent's `EnsureParentId` API](https://www.elastic.co/guide/en/apm/agent/dotnet/current/public-api.html#api-transaction-ensure-parent-id)

### Additional contract requirements

Calling `ensureParentId` on a transaction ensures that it has a parent ID: it creates and stores an ID when none exists, preserves an existing parent ID, and does not replace the stored ID on repeated calls.
