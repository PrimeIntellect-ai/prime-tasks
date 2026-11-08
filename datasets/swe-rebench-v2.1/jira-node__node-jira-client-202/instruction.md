Empty properties string causing Internal Server Error on findIssue API call
On JIRA API v2, passing in an empty properties query string param is causing an Internal Server Error. Removing the param entirely or setting it to a `*` fixes the issue. url.format takes null or undefined values in the querystring and sets them to an empty string.

[HIDDEN]

Correctly formats the querystring and findIssue returns valid json.

### Additional contract requirements

- When no `properties` value is supplied, `findIssue` must send the exact query parameter value `properties=*all` (the same non-empty default used for `fields`), not `*` and not an empty string.
- `findIssue` returns a Promise that resolves to the issue JSON object returned by the JIRA REST API.
