Update teams_discussion_comments.go
Relates to: #1422 and #1387.

It seems that the [original blog post](https://developer.github.com/changes/2020-01-21-moving-the-team-api-endpoints/) that we were basing #1387 on didn't mention these changes.

This issue will be for updating `teams_discussion_comments.go`.

The work involved here is to update every endpoint listed here:
https://developer.github.com/v3/teams/discussion_comments/
Note that #1400 can be used as a model because most endpoints have two ways to call them: `*ByID` and `*BySlug`. The same pattern should be followed for these updates.

This would be a great PR for any new contributor to this repo or a new Go developer.
All contributions are greatly appreciated!

Feel free to volunteer for any issue and the issue can be assigned to you so that others don't attempt to duplicate the work.

Please check out our [CONTRIBUTING.md](https://github.com/google/go-github/blob/master/CONTRIBUTING.md) guide to get started.

Thank you!

### Additional contract requirements

The following public methods must be added to `TeamsService` in the `github` package. Each returns the listed values and issues the listed HTTP method against the listed request path:

- `ListCommentsByID(ctx context.Context, orgID int64, teamID int64, discussionNumber int, options *DiscussionCommentListOptions) ([]*DiscussionComment, *Response, error)` — `GET organizations/{orgID}/team/{teamID}/discussions/{discussionNumber}/comments`.
- `ListCommentsBySlug(ctx context.Context, org string, slug string, discussionNumber int, options *DiscussionCommentListOptions) ([]*DiscussionComment, *Response, error)` — `GET orgs/{org}/teams/{slug}/discussions/{discussionNumber}/comments`.
- `GetCommentByID(ctx context.Context, orgID int64, teamID int64, discussionNumber int, commentNumber int) (*DiscussionComment, *Response, error)` — `GET organizations/{orgID}/team/{teamID}/discussions/{discussionNumber}/comments/{commentNumber}`.
- `GetCommentBySlug(ctx context.Context, org string, slug string, discussionNumber int, commentNumber int) (*DiscussionComment, *Response, error)` — `GET orgs/{org}/teams/{slug}/discussions/{discussionNumber}/comments/{commentNumber}`.
- `CreateCommentByID(ctx context.Context, orgID int64, teamID int64, discussionNumber int, comment DiscussionComment) (*DiscussionComment, *Response, error)` — `POST organizations/{orgID}/team/{teamID}/discussions/{discussionNumber}/comments`, sending the comment as the JSON request body.
- `CreateCommentBySlug(ctx context.Context, org string, slug string, discussionNumber int, comment DiscussionComment) (*DiscussionComment, *Response, error)` — `POST orgs/{org}/teams/{slug}/discussions/{discussionNumber}/comments`, sending the comment as the JSON request body.
- `EditCommentByID(ctx context.Context, orgID int64, teamID int64, discussionNumber int, commentNumber int, comment DiscussionComment) (*DiscussionComment, *Response, error)` — `PATCH organizations/{orgID}/team/{teamID}/discussions/{discussionNumber}/comments/{commentNumber}`, sending the comment as the JSON request body.
- `EditCommentBySlug(ctx context.Context, org string, slug string, discussionNumber int, commentNumber int, comment DiscussionComment) (*DiscussionComment, *Response, error)` — `PATCH orgs/{org}/teams/{slug}/discussions/{discussionNumber}/comments/{commentNumber}`, sending the comment as the JSON request body.
- `DeleteCommentByID(ctx context.Context, orgID int64, teamID int64, discussionNumber int, commentNumber int) (*Response, error)` — `DELETE organizations/{orgID}/team/{teamID}/discussions/{discussionNumber}/comments/{commentNumber}`.
- `DeleteCommentBySlug(ctx context.Context, org string, slug string, discussionNumber int, commentNumber int) (*Response, error)` — `DELETE orgs/{org}/teams/{slug}/discussions/{discussionNumber}/comments/{commentNumber}`.

`DiscussionCommentListOptions` accepts a `Direction` field whose value is sent as the `direction` query parameter.
