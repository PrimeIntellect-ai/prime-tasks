[ADAP-622] [Regression] Authorised views `grant_access_to` exceeded rate limit error
### Is this a regression in a recent version of dbt-bigquery?

- [X] I believe this is a regression in dbt-bigquery functionality
- [X] I have searched the existing issues, and I could not find an existing issue for this regression

### Current Behavior

When creating many authorized views on a single dataset in a short amount of time, the [bigquery update dataset limit](https://cloud.google.com/bigquery/quotas#dataset_limits) of 5 update operations per 10 seconds is quickly reached.

This is unavoidable and expected the first time the authorized views are created, but on subsequent dbt runs when the authorized views already exist, I am now also seeing this limit being hit which previously was not happening.

When the dbt logs show this warning:
```
BigQuery adapter: Access entry <AccessEntry: role=None, view={'projectId': '...', 'datasetId': '...', 'tableId': '...'}> already exists in dataset
```
BigQuery logs are giving this error
```
NOTICE 2023-06-13T20:26:42.048907Z [protoPayload.serviceName: bigquery.googleapis.com] [protoPayload.methodName: google.cloud.bigquery.v2.DatasetService.PatchDataset] [protoPayload.resourceName:...] [protoPayload.authenticationInfo.principalEmail:...] audit_log, method: "google.cloud.bigquery.v2.DatasetService.PatchDataset", principal_email: "..."
ERROR 2023-06-13T20:26:42.439870Z [protoPayload.serviceName: bigquery.googleapis.com] [protoPayload.methodName: google.cloud.bigquery.v2.DatasetService.PatchDataset] [protoPayload.resourceName:...] [protoPayload.authenticationInfo.principalEmail:...] Exceeded rate limits: too many dataset metadata update operations for this dataset. For more information, see https://cloud.google.com/bigquery/docs/troubleshoot-quotas
ERROR 2023-06-13T20:26:42.630266Z [protoPayload.serviceName: bigquery.googleapis.com] [protoPayload.methodName: google.cloud.bigquery.v2.DatasetService.PatchDataset] [protoPayload.resourceName:...] [protoPayload.authenticationInfo.principalEmail:...] Exceeded rate limits: too many dataset metadata update operations for this dataset. For more information, see https://cloud.google.com/bigquery/docs/troubleshoot-quotas
```

### Expected/Previous Behavior

Previously when an authorized view already existed in a dataset, using `grant_access_to` would show the `already exists in dataset` warning but not cause an additional unnecessary dataset update.

### Steps To Reproduce

With dbt-bigquery >= v1.4.2, create a lot of authorized views (>5) on a single dataset and do two dbt runs.

After the second run, in gcp logs explorer run the following query to view rate exceeded errors
```
resource.type = "bigquery_dataset"
protoPayload.methodName:"google.cloud.bigquery.v2.DatasetService.PatchDataset"
```





### Relevant log output

_No response_

### Environment

```markdown
- OS: macos 13.4
- Python:3.9.6
- dbt-core (working version):1.4.6
- dbt-bigquery (working version):1.4.1
- dbt-core (regression version):1.4.6
- dbt-bigquery (regression version):1.4.2
```


### Additional Context

This issue is due to a [recent change](https://github.com/dbt-labs/dbt-bigquery/pull/404) with the BigQueryAdapter grant_access_to() method which now will call the bigquery patch.dataset api even when the authorized view already exists in the dataset.

I don't believe this is expected behaviour because of the relatively low limit for this operation, calling it when unnecessary has the potential to significantly impact performance.
