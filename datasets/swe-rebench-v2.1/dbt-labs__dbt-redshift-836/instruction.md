[Bug] dbt-redshift should not use `group_federation=true` when connecting with Serverless.
Group_federation parameter is not required with Serverless and makes the redshift connector call `getclustercredentialswithIAM` instead of `get_credentials` - the former doesn't exist for Serverless.
