OIDC: Option for Username instead of Email
It would be nice if one could configure it so when logging in with OIDC is reads the username field rather than email field.

Edit: Biggest reason is if my OIDC users want to share their bookmarks, they'd be able to do that without sharing their email address with the world (or just other users if not sharing publicly).

### Additional contract requirements

- Add a public function `generate_username(email: str, claims: dict) -> str` in the module `bookmarks.utils`. It returns the username for a newly authenticated OIDC user: the value of the claim named by the `OIDC_USERNAME_CLAIM` setting when that claim is present and non-empty, otherwise the supplied email. The returned username is Unicode-normalized with NFKC.
- When OIDC is enabled, the `OIDC_USERNAME_CLAIM` setting defaults to `email`.
- When OIDC is enabled, the `OIDC_RP_SCOPES` setting defaults to `openid email profile`.
