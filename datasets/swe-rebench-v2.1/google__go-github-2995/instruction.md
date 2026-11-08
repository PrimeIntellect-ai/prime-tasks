Webhook type for repository edits is missing default branch
Repository edit events can include default branch changes and are dropped during parsing because it's missing from the types. (https://docs.github.com/en/webhooks/webhook-events-and-payloads?actionType=edited#repository)

```json
{
  "action": "edited",
  "changes": {"default_branch": {"from": "master"}},
  "enterprise": {
    "description": "...",
    "id": 1,
    "name": "Inc"
  },
  "organization": {
    "id": 1,
    "login": "Inc"
  },
  "repository": {
    "id": 1,
    "name": "repo",
    "full_name": "Owner/repo",
    "owner": {},
    "default_branch": "main"
  },
  "sender": {
    "id": 1,
    "login": "user"
  }
}
```

### Additional contract requirements

- A repository edit event's `changes.default_branch.from` value must be available after the webhook payload is parsed.
- Add a public type `EditDefaultBranch` in package `github` with a public `From` field holding the previous default-branch name.
- Add a public method `EditChange.GetDefaultBranch() *EditDefaultBranch` that returns the receiver's default-branch change, or nil when the receiver is nil.
- Add a public method `EditDefaultBranch.GetFrom() string` that returns the previous default-branch name, or an empty string when the receiver or its `From` field is nil.
