Add support for CommitID, InReplyTo, and SubjectType to DraftReviewComment
Currently these fields are missing: https://docs.github.com/en/rest/pulls/comments?apiVersion=2022-11-28#create-a-review-comment-for-a-pull-request

Happy to raise a PR to add support

### Additional contract requirements

- Provide nil-safe `GetCommitID`, `GetInReplyTo`, and `GetSubjectType` accessors on `DraftReviewComment`. They return the field value when set, and the Go zero value when the field or receiver is nil (`""` for `CommitID` and `SubjectType`; `0` for `InReplyTo`).
