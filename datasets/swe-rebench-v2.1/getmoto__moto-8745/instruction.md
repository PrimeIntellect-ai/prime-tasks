[RDS] Unsupported `ManageMasterUserPassword` on create_db_cluster
According to [boto3 docs](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/rds/client/create_db_cluster.html), the `MasterUserPassword` can’t be specified if `ManageMasterUserPassword` is turned on.

As of v5.1.1, the `MasterUserPassword` is a mandatory field on the `create_db_cluster` function

Example test:
```
import boto3
from moto import mock_aws

@mock_aws
def test_create_db_cluster():
    rds = boto3.client('rds', region_name='us-east-1')

    # Create the DB cluster with a dummy password
    response = rds.create_db_cluster(
        DBClusterIdentifier='my-cluster',
        Engine='aurora-mysql',
        MasterUsername='myuser',
        ManageMasterUserPassword=True,
        DBClusterParameterGroupName='default-aurora-mysql57',
        VpcSecurityGroupIds=['sg-12345678'],
    )

test_create_db_cluster()
```

Result:
`botocore.exceptions.ClientError: An error occurred (InvalidParameterValue) when calling the CreateDBCluster operation: The parameter MasterUserPassword must be provided and must not be blank.`
