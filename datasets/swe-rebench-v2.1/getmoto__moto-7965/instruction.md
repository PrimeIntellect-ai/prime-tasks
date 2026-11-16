Organizations `create_account()` should create an IAM role in the new "account"
Hello! Long time, first time. Thanks for the library -- it's hugely useful. I have a (hopefully) small enhancement request.

In AWS Organizations, calling the `organizations:CreateAccount` API results in an IAM role named `OrganizationAccountAccessRole` being created in the new account. The name of the role can be customized using the `RoleName` parameter ([boto3 `Organizations.Client.create_account()` docs](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/organizations/client/create_account.html)).

I would like to propose mirroring that behavior in moto. I could probably sort out how to implement this, but first I wanted to open an issue to see if it's philosophically in line with moto; I don't know if there's any precedent for cross-service interaction like this.

Here are a couple of tests that illustrate the desired behavior:

```python
import os

import boto3
from moto import mock_aws


@mock_aws
def test_create_account_creates_role():
    orgs_client = boto3.client('organizations', region_name='us-west-2')
    _ = orgs_client.create_organization()
    account = orgs_client.create_account(
        AccountName='test_account',
        Email='test@test.xyz',
    )
    account_id = account['CreateAccountStatus']['AccountId']

    os.environ['MOTO_ACCOUNT_ID'] = account_id
    iam_client = boto3.client('iam')
    org_role = iam_client.get_role(RoleName='OrganizationAccountAccessRole')
    assert org_role


@mock_aws
def test_create_account_creates_custom_role():
    orgs_client = boto3.client('organizations', region_name='us-west-2')
    _ = orgs_client.create_organization()
    account = orgs_client.create_account(
        AccountName='test_account',
        Email='test@test.xyz',
        RoleName='CustomOrganizationRole',
    )
    account_id = account['CreateAccountStatus']['AccountId']

    os.environ['MOTO_ACCOUNT_ID'] = account_id
    iam_client = boto3.client('iam')
    org_role = iam_client.get_role(RoleName='CustomOrganizationRole')
    assert org_role
```

Both tests result in an exception on the `get_role()` calls: `botocore.errorfactory.NoSuchEntityException: An error occurred (NoSuchEntity) when calling the GetRole operation: Role CustomOrganizationRole not found`
