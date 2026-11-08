AuditEntry is missing referrer field
The [AuditEntry](https://github.com/google/go-github/blob/a54bc7da1d91a3d2de234741640965ac9ece6d74/github/orgs_audit_log.go#L45) structs is missing `referrer` field which is a useful information to understand more about the changes when it comes into protected_branch action in audit log.

Following is an example entry from Github API response which does have the `referrer` field.

```json
[
    {
        "@timestamp": 1702649229027,
        "_document_id": "RbYZGywxRSadhVVKTSGP5g",
        "action": "protected_branch.policy_override",
        "actor": "bob",
        "actor_id": 111111,
        "actor_location":
        {
            "country_code": "DE"
        },
        "after": "66480649c9e042c93287ce387611bd1d785a977c",
        "before": "761e880ab6459f8f5a1cd2b4e0e1f1041df74f92",
        "branch": "refs/heads/main",
        "business": "hidden",
        "business_id": 11111,
        "created_at": 1702649229027,
        "external_identity_nameid": "bob@domain.ltd",
        "external_identity_username": "bob@domain.ltd",
        "operation_type": "modify",
        "org": "hidden",
        "org_id": 111111,
        "overridden_codes":
        [
            "required_status_checks"
        ],
        "public_repo": false,
        "reasons":
        [
            {
                "code": "required_status_checks",
                "message": "3 of 3 required status checks have not succeeded: 2 expected and 1 failing."
            }
        ],
        "referrer": "https://github.com/hidden/test/pull/332",
        "repo": "hidden/test",
        "repo_id": 111111,
        "user_agent": "Mozilla/5.0 (Macintosh Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
]
```
