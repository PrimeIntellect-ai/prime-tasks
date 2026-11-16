Add support for "fields" query param on `findIssue` method
It would be great to be able to restrict the fields returned for an issue for the `findIssue` method by using the "fields" query param that the REST API already supports:

https://docs.atlassian.com/jira/REST/server/#api/2/issue-getIssue

### Additional contract requirements

The `findIssue` method of the Jira API client (module `src/jira.js`) has the signature
`findIssue(issueNumber, expand, fields, properties, fieldsByKeys)`:

- `issueNumber` – the full issue key (e.g. `PK-100`). Required string.
- `expand` – optional comma-separated list of expansion resources; defaults to an empty string when omitted.
- `fields` – optional comma-separated list of field IDs or keys to return; defaults to `*all` when omitted.
- `properties` – optional comma-separated list of issue properties to include; defaults to an empty string when omitted.
- `fieldsByKeys` – optional boolean indicating whether the values in `fields` are interpreted as field keys rather than IDs; defaults to `false` when omitted.

The request URL always includes the query parameters `expand`, `fields`, `properties`, and `fieldsByKeys`, using the defaults when the corresponding argument is omitted, and these parameters appear in that order.
