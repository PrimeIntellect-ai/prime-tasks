Remove `with_expiration` from `fetch_invite`
https://github.com/discord/discord-api-docs/pull/7424

### Additional contract requirements

- `fetch_invite` is a REST client method that takes an invite (a raw invite code string or an `InviteCode`) and an optional `with_counts` flag that defaults to `True`, and returns the fetched `Invite`.
- The outgoing request carries the `with_counts` query parameter and never carries a `with_expiration` query parameter.
- Passing a `with_expiration` argument to `fetch_invite` raises `TypeError`.
