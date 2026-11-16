Use org membership instead of listing to determine upload status
Use https://developer.github.com/v3/orgs/members/#check-membership in `ci.webauth.user_information()`. Currently private members are invisible.

### Additional contract requirements

- `ci.webauth.user_information(token, org_name='openaddresses')` accepts an optional `org_name` argument naming the GitHub organization whose membership is checked; when omitted it defaults to `'openaddresses'`.
- Membership is checked against the GitHub organization-membership endpoint `GET /orgs/{org}/members/{username}`, where `{org}` is the selected organization and `{username}` is the authenticated user's login.
- It returns a tuple `(login, avatar_url, is_member)`: `login` is the authenticated user's GitHub username, `avatar_url` is the URL of the user's avatar image, and `is_member` is `True` when the membership check returns a 2xx status and `False` otherwise.
