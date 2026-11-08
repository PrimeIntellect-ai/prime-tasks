Question on adding fixVersions
Hello,

Thank you for your project. It is very useful!

I've a question; I would like to update the fixVersions field of an issue. I thought I could use the same approach as described in the cookbook 'edit jira issue (implicit)'. So using a AddStringOperation like in:

```
	var operations = &models.UpdateOperations{}
	err = operations.AddArrayOperation("fixVersions", map[string]string{
		"v1": "add",
	})

```
However I get an error that I need to "Specify a valid version 'id' or 'name' for fixVersions"".

In examples from other languages I see people explicitly including 'name'. However this is not possible with an arrayOperation as it expects a map[string]string.

Do you know how to set the fixVersions field?

thanks

Stephan


PS in the cookbook code it says "atlassian", but it should say "client"

### Additional contract requirements

- Updating an issue's `fixVersions` field must be possible with versions identified by a valid `id` or `name`, not only through a flat string-to-string mapping.
- `UpdateOperations` must provide a method `AddMultiRawOperation(customFieldID string, mappings []map[string]interface{}) error`. It appends one update block for the given field, containing the given operations in the given order. For example, calling it with field `fixVersions` and the operations `{"add": {"id": "10001"}}` and `{"remove": {"name": "Version 00"}}` produces the update payload `{"update":{"fixVersions":[{"add":{"id":"10001"}},{"remove":{"name":"Version 00"}}]}}`.
- Calling `AddMultiRawOperation` with an empty field identifier returns an error.
