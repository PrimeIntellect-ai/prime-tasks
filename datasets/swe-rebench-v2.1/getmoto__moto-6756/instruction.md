[Feature request] SageMaker list and notebook instances
Currently Moto can create a fake SageMaker notebook instance, and delete it, and describe it's lifecycle config, and list tags for it.

I want to add functionality to list notebook instances, including the `list_notebook_instances` paginator.

This is something I'll attempt myself. But I'm just raising a ticket so other people get visibility.

### Additional contract requirements

- Add a public SageMaker client method `list_notebook_instances` that lists the notebook instances in the account. It accepts the optional parameters `SortBy` (default `"Name"`), `SortOrder` (default `"Ascending"`), `NameContains`, `StatusEquals`, `MaxResults` and `NextToken`.
- `SortBy` selects the attribute used for ordering and is one of `"Name"`, `"CreationTime"` or `"Status"`. `SortOrder` selects the direction and is either `"Ascending"` or `"Descending"`.
- `NameContains` keeps only instances whose name contains the given substring. `StatusEquals` keeps only instances whose status equals the given value.
- `MaxResults` limits the number of instances returned in a single call. When more instances remain, the response contains a `NextToken` string that can be passed back as `NextToken` to retrieve the following page; when no further instances remain, the response omits `NextToken`.
- The response is a dict with key `NotebookInstances`, a list of notebook instance dicts. Each dict contains at least `NotebookInstanceName` and `NotebookInstanceStatus`.
