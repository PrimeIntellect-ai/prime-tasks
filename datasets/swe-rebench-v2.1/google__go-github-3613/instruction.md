BUG: Remove Sub Issue uses incorrect endpoint
## SubIssues Bug

Recent addition for managing Sub Issues uses wrong endpoint:

`Failed to remove sub-issue: 404 Not Found, DELETE https://api.github.com/repos/REPO/OWNER/issues/ISSUE_NUMBER/sub_issues: 404 Not Found []`

https://github.com/google/go-github/blob/master/github/sub_issue.go#L51-L53

This endpoint (however inconsistent) must be singular form:

https://docs.github.com/en/rest/issues/sub-issues?apiVersion=2022-11-28#remove-sub-issue
