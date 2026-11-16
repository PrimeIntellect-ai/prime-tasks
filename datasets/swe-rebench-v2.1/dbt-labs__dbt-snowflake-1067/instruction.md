[Bug] Replace underscores with hyphens in account identifiers
### Is this a new bug in dbt-snowflake?

- [X] I believe this is a new bug in dbt-snowflake
- [X] I have searched the existing issues, and I could not find an existing issue for this bug

### Current Behavior

Domain names containing underscores cause SSL issues (especially on Python 3.11+)

### Expected Behavior

dbt-snowflake (via snowflake-connector-python) successfully connects to any Snowflake account, regardless of domain name + Python version, by replacing underscores with hyphens

### Steps To Reproduce

1. Have a Snowflake account containing an underscore
2. Try connecting
3. Change the account name to use a hyphen instead
4. Succeeds

### Relevant log output

_No response_

### Environment

```markdown
- Python: 3.11
- dbt-core: 1.8+
- dbt-snowflake: 1.8+
```


### Additional Context

https://docs.snowflake.com/en/user-guide/admin-account-identifier#account-name

> URLs that include underscores can sometimes cause issues for certain features, such as Okta SSO/SCIM. For this reason, Snowflake also supports a version of the account name that substitutes the hyphen character (-) in place of the underscore character.

A better resolution would be to make this fix within the Snowflake Python connector:
- https://github.com/snowflakedb/snowflake-connector-python/issues/1839#issuecomment-2142535852
