[RDS] `create_global_cluster` does not return `Endpoint`
The RDS API call `create_global_cluster` returns an `Endpoint` value which contains the global writer endpoint for the newly created global cluster. This value was added into boto3 in version 1.35.46 (https://github.com/boto/boto3/blob/develop/CHANGELOG.rst)

> https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds/client/create_global_cluster.html
>
> Endpoint (string) –
> The writer endpoint for the new global database cluster. This endpoint always points to the writer DB instance in the current primary cluster.

Below is an example of reproducing the issue.

```
Python 3.12.2 (main, Feb 20 2024, 09:09:44) [GCC 8.5.0 20210514 (Red Hat 8.5.0-18)] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import moto
>>> moto.__version__
'5.0.28'

>>> import boto3
>>> boto3.__version__
'1.36.21'

>>> mock = moto.mock_aws()
>>> mock.start()

>>> rds = boto3.client("rds")
>>> rds.create_global_cluster(GlobalClusterIdentifier="test-global-cluster", Engine="aurora-postgresql", EngineVersion="16.4")
{'GlobalCluster': {'GlobalClusterIdentifier': 'test-global-cluster', 'GlobalClusterResourceId': 'cluster-2d4ab38f', 'GlobalClusterArn': 'arn:aws:rds::123456789012:global-cluster:test-global-cluster', 'Status': 'available', 'Engine': 'aurora-postgresql', 'EngineVersion': '16.4', 'StorageEncrypted': False, 'DeletionProtection': False, 'GlobalClusterMembers': []}, 'ResponseMetadata': {'RequestId': 'auOPmQrF8HvBOsqdgKgmc4WwAw42pZIPO3hMMF1qEq95ct7yrd5T', 'HTTPStatusCode': 200, 'HTTPHeaders': {'server': 'amazon.com', 'date': 'Tue, 18 Feb 2025 16:31:39 GMT', 'x-amzn-requestid': 'auOPmQrF8HvBOsqdgKgmc4WwAw42pZIPO3hMMF1qEq95ct7yrd5T'}, 'RetryAttempts': 0}}
```
