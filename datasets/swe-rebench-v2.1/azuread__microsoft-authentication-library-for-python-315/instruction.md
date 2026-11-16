MSAL shouldn't remove Refresh Token upon receiving invalid_grant
**Describe the bug**
MSAL shouldn't remove Refresh Token upon receiving `invalid_grant`.

**To Reproduce**
When

1. ARM (`https://management.azure.com/.default`) doesn't require MFA
2. VM SSH (`https://pas.windows.net/CheckMyAccess/Linux/.default`) requires MFA

This script will cause the RT of ARM to be removed, making subsequence ARM requests fail:

```py
import msal

app = msal.PublicClientApplication("04b07795-8ddb-461a-bbee-02f9e1bf7b46",
                                   authority="https://login.microsoftonline.com/organizations")
result = app.acquire_token_interactive(["https://management.azure.com/.default"])
print(app.token_cache._cache['RefreshToken'])

account = app.get_accounts(result['id_token_claims']['preferred_username'])[0]
result = app.acquire_token_silent_with_error(['https://pas.windows.net/CheckMyAccess/Linux/.default'], account)
print(result)
print(app.token_cache._cache['RefreshToken'])
```

**Expected behavior**
The refresh token should be persisted so that ARM request can still work.

**What you see instead**
Output (prettified):

```json
{
    "92bebeb6-c875-4f40-b2d2-f6324929f04a.54826b22-38d6-4fb2-bad9-b7b93a3e9c5a-login.microsoftonline.com-refreshtoken-04b07795-8ddb-461a-bbee-02f9e1bf7b46--https://management.azure.com/user_impersonation https://management.azure.com/.default": {
        "credential_type": "RefreshToken",
        "secret": "...",
        "home_account_id": "92bebeb6-c875-4f40-b2d2-f6324929f04a.54826b22-38d6-4fb2-bad9-b7b93a3e9c5a",
        "environment": "login.microsoftonline.com",
        "client_id": "04b07795-8ddb-461a-bbee-02f9e1bf7b46",
        "target": "https://management.azure.com/user_impersonation https://management.azure.com/.default",
        "family_id": "1"
    }
}

{
    "error": "invalid_grant",
    "error_description": "AADSTS50076: Due to a configuration change made by your administrator, or because you moved to a new location, you must use multi-factor authentication to access 'ce6ff14a-7fdc-4685-bbe0-f6afdfcfa8e0'.\r\nTrace ID: 3ddb15bc-d1d1-4d67-9b9f-77c0beb99000\r\nCorrelation ID: d8e4d35b-419e-4b25-8152-c833f497c38e\r\nTimestamp: 2021-03-01 11:21:13Z",
    "error_codes": [
        50076
    ],
    "timestamp": "2021-03-01 11:21:13Z",
    "trace_id": "3ddb15bc-d1d1-4d67-9b9f-77c0beb99000",
    "correlation_id": "d8e4d35b-419e-4b25-8152-c833f497c38e",
    "error_uri": "https://login.microsoftonline.com/error?code=50076",
    "suberror": "basic_action",
    "classification": "basic_action"
}

{}
```

**The MSAL Python version you are using**
1.9.0

**Additional context**
`invalid_grant` in this case only means the RT is invalid for acquiring an AT for VM SSH, but doesn't necessarily mean it can't be used to acquire an AT for ARM.

Use Conditional Access to configure MFA requirement for VM SSH:

![image](https://user-images.githubusercontent.com/4003950/109492421-f1def980-7ac5-11eb-942f-0a5eaaf05f42.png)

![image](https://user-images.githubusercontent.com/4003950/109492054-56e61f80-7ac5-11eb-886c-82aed88c65a0.png)
