Ephemeral Data Context Failing with permission denied on file
We are migrating from GX0.18 to GX 1.x and even though we are using Ephemeral Data Context and we are not using analytics, we are still getting below error:

Permission denied: '/root/.great_expectations/great_expectations.conf
The error is coming as part of the [HIDDEN] even though we have analytics usage set as False in the data context and even though we are using ephemeral context.
This is happening with Databricks DBR15.4 on a streaming load, inside a forEachBatch.
Do you have any idea?
Why is GX checking for the file if we are using ephemeral and also turning analytics off?

https://discourse.greatexpectations.io/t/ephemeral-data-context-failing-with-permission-denied-on-file/2235

### Additional contract requirements

When an ephemeral Data Context has analytics disabled, initializing it must not access the root Great Expectations configuration file to obtain an OSS ID.
