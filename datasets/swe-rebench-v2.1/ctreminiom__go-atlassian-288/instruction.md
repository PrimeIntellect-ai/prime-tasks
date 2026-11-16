Add group user picker
**Is your feature request related to a problem? Please describe.**
This does not exists.
https://developer.atlassian.com/cloud/jira/platform/rest/v2/api-group-group-and-user-picker/#api-rest-api-2-groupuserpicker-get

**Additional context**
Neither in V2 nor V3

### Additional contract requirements

The group-user picker must be available through the normal Jira API v2 and v3 clients. A lookup must send the search query to the version-appropriate `/rest/api/{2-3}/groupuserpicker` endpoint and return group and user data represented by the response.

In Go, construct either client with `jira/v2.New` or `jira/v3.New`; each returned `Client` exposes the lookup as `GroupUserPicker`. Its `Find` method accepts a `context.Context` and a `*models.GroupUserPickerFindOptionScheme` from `pkg/infra/models`, and returns `*models.GroupUserPickerFindScheme`, `*models.ResponseScheme`, and an error. Set the search text with the option's `Query` field. The result exposes `Groups` and `Users`; group entries are available under `result.Groups.Groups` and expose `GroupID` and `Name`, while user entries are available under `result.Users.Users` and expose `AccountID` and `DisplayName`.
