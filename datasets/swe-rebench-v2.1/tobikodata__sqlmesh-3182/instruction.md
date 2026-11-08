Add support for quota project on BigQuery
# What's a quota project?
BigQuery allows to have custom quotas: https://cloud.google.com/bigquery/docs/custom-quotas
For instance, it allows to control the amount of TB that can be queried per user.

# What's the default?
The default appears to be `quota project_id` from the credentials such as in JSON credentials:
```
{
  "account": "",
  "client_id": "xyz.apps.googleusercontent.com",
  "client_secret": "xyz",
  "quota_project_id":  "my_quota_project",
  "refresh_token": "xyz",
  "type": "authorized_user",
  "universe_domain": "googleapis.com"
}
```

# How it is used?
The BigQuery client from Python SDK has a property that allows to override the `quota_project` through `client_options`.
The option is used in https://github.com/googleapis/python-cloud-core/blob/e5fb3ea79ea70d538a97c758a33d0b3ab7d1182c/google/cloud/client/__init__.py#L184-L187

### Additional contract requirements

- `BigQueryConnectionConfig` accepts an optional string configuration value named `quota_project`.
- When `quota_project` is specified without `project`, configuration validation fails with a `ConfigError` whose message contains the exact text "you must also specify the `project` field".
- When a `quota_project` is configured, the BigQuery client is created with `client_options` whose `quota_project_id` is set to the configured value.
- When `quota_project` is omitted, the quota project associated with the credentials remains the default for BigQuery requests.
