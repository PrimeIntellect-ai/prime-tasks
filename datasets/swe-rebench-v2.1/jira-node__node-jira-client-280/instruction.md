Get Comments by ID
The Jira API supports getting comments by ID, but this does not seem to be implemented in the library.

[Jira Doc](https://developer.atlassian.com/cloud/jira/platform/rest/v3/#api-rest-api-3-comment-list-post)

### Additional contract requirements

- Add a public method `getComments(issueId)` to the Jira API client (the default export of `src/jira.js`). `issueId` is a number identifying the issue. It returns a Promise resolving to the result of the request to the path `.../issue/{issueId}/comment`.
- Add a public method `getComment(issueId, commentId)` to the Jira API client. `issueId` and `commentId` are numbers identifying the issue and the comment. It returns a Promise resolving to the result of the request to the path `.../issue/{issueId}/comment/{commentId}`.
- Add a public method `deleteComment(issueId, commentId)` to the Jira API client. `issueId` and `commentId` are numbers identifying the issue and the comment. It deletes the specified comment by issuing a request to the path `.../issue/{issueId}/comment/{commentId}`.
