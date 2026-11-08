Add notify API
https://docs.atlassian.com/jira/REST/latest/#api/2/issue-notify

### Additional contract requirements

Expose `JiraApi.issueNotify(issueId, notificationBody)`, accepting an issue identifier and a notification payload object. It must send that payload in a POST request to the Jira issue-notify endpoint `/issue/{issueId}/notify` for the specified issue.
