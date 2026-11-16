Automatic re-authorizing with application key does not work
When it re-authorizes, it should use the same application key used for the original authentication, but it's using the account ID.

### Additional contract requirements

- `AbstractAccountInfo.get_account_id_or_app_key_id()` returns the identifier that was used to authorize the current session: the account ID when the session was authorized with the account ID, or the application-key ID when it was authorized with an application key.
- `InMemoryAccountInfo.get_account_id_or_app_key_id()` returns that identifier.
- `SqliteAccountInfo.get_account_id_or_app_key_id()` returns the stored identifier, falling back to the account ID when no identifier was stored (for example, for account information written before this change).
- `SqliteAccountInfo.__init__(file_name=None, last_upgrade_to_run=None)` accepts an optional `last_upgrade_to_run` argument that selects how far the database schema upgrades are applied.
- `SqliteAccountInfo.set_auth_data_with_schema_0_for_test(account_id, auth_token, api_url, download_url, minimum_part_size, application_key, realm)` stores authentication data in the original (pre-upgrade) schema.
- `RawSimulator.expire_auth_token(auth_token)` marks an issued authorization token as expired, so that the next API call using it fails with an `InvalidAuthToken` error whose code is `auth_token_expired`.
