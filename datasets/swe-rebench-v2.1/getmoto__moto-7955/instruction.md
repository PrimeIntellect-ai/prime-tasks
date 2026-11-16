Incorrect behavior of SageMaker Client Search Method
# Environment Information
- Python Version: 3.8.12
- boto3 == 1.24.4
- pytest == 8.3.2
- moto == 5.0.11

# Documentation Reference

According to the [latest moto documentation](https://docs.getmoto.org/en/latest/docs/services/sagemaker.html) for sagemaker implemented services, the following methods are implemented:
- [X] create_model_package_group
- [X] list_model_package_groups
- [X] search

# Problem Description

I am currently using moto test the retrieval of model package groups based on certain tags. I created some model groups for testing, but when calling the method `sagemaker_client.search` no model package groups were returned, even when using only the `Resource` keyword. To ensure this was a problem of the search method I also used the list_model_groups method and I was able to visualize all the model package groups as expected.

# Minimal Example

**search_model_group.py**
```python
import boto3

class ModelGroupFinder:
    def __init__(self):
        self.sm_client = boto3.client('sagemaker')

    def get_model_groups_with_search_method(self):
        search_results = self.sm_client.search(
            Resource='ModelPackageGroup',
            SearchExpression={
                'Filters': [{
                    'Name': 'Tags.RegisteredBySourceRoleArn',
                    'Operator': 'Equals',
                    'Value': 'arn:aws:iam::123456789012:role/DSSourceRole'}]}
        )
        return search_results

    def get_model_groups_with_list_model_groups_method(self):
        list_model_results = self.sm_client.list_model_package_groups()
        return list_model_results
```

**test_model_groups.py**
```python
import boto3
from moto import mock_aws
from .search_model_group import ModelGroupFinder
from pprint import pprint

MOCK_SOURCE_ROLE_ARN = 'arn:aws:iam::123456789012:role/DSSourceRole'


def mock_model_groups():
    sm_client = boto3.client('sagemaker')
    sm_client.create_model_package_group(
        ModelPackageGroupName='model-test_DEV',
        ModelPackageGroupDescription='Model group in DEV environment.',
        Tags=[
            {
                'Key': 'RegisteredBySourceRoleArn',
                'Value': MOCK_SOURCE_ROLE_ARN
            }
        ]
    )
    sm_client.create_model_package_group(
        ModelPackageGroupName='model-test_PROD',
        ModelPackageGroupDescription='Model group in PROD environment.',
        Tags=[
            {
                'Key': 'RegisteredBySourceRoleArn',
                'Value': MOCK_SOURCE_ROLE_ARN
            }
        ]
    )
    sm_client.create_model_package_group(
        ModelPackageGroupName='model-test2_DEV',
        ModelPackageGroupDescription='Model group in DEV environment.',
        Tags=[
            {
                'Key': 'RegisteredBySourceRoleArn',
                'Value': 'arn:aws:iam::123456789012:role/OtherSourceRole'
            }
        ]
    )

@mock_aws
def test_search_function():
    mock_model_groups()
    model_group_finder = ModelGroupFinder()
    model_groups = model_group_finder.get_model_groups_with_search_method()
    print('Sagemaker Search Function: ')
    pprint(model_groups)


@mock_aws
def test_list_function():
    mock_model_groups()
    model_group_finder = ModelGroupFinder()
    model_groups = model_group_finder.get_model_groups_with_list_model_groups_method()
    print('List Model Package Group Function')
    pprint(model_groups)
```

When running `pytest -s test_model_groups.py` the following print statements are shown in the console:

`Sagemaker Search Function:`
```json
{
  "ResponseMetadata": {
    "HTTPHeaders": {
      "date": "Fri, 26 Jul 2024 14:42:54 GMT",
      "server": "amazon.com",
      "x-amzn-requestid": "eKKGgAfq4hDFlUGdxTDhFLuOu5VPQTAnoIN1Zc7aDxL9HYOjZ1Xd"
    },
    "HTTPStatusCode": 200,
    "RequestId": "eKKGgAfq4hDFlUGdxTDhFLuOu5VPQTAnoIN1Zc7aDxL9HYOjZ1Xd",
    "RetryAttempts": 0
  },
  "Results": []
}

`List Model Package Group Function:`
```json
{
  "ModelPackageGroupSummaryList": [
    {
      "CreationTime": datetime.datetime(2024, 7, 26, 17, 42, 54, 711092, tzinfo=tzutc()),
      "ModelPackageGroupArn": "arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test_DEV",
      "ModelPackageGroupDescription": "Model group in DEV environment.",
      "ModelPackageGroupName": "model-test_DEV",
      "ModelPackageGroupStatus": "Completed"
    },
    {
      "CreationTime": datetime.datetime(2024, 7, 26, 17, 42, 54, 712037, tzinfo=tzutc()),
      "ModelPackageGroupArn": "arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test_PROD",
      "ModelPackageGroupDescription": "Model group in PROD environment.",
      "ModelPackageGroupName": "model-test_PROD",
      "ModelPackageGroupStatus": "Completed"
    },
    {
      "CreationTime": datetime.datetime(2024, 7, 26, 17, 42, 54, 712727, tzinfo=tzutc()),
      "ModelPackageGroupArn": "arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test2_DEV",
      "ModelPackageGroupDescription": "Model group in DEV environment.",
      "ModelPackageGroupName": "model-test2_DEV",
      "ModelPackageGroupStatus": "Completed"
    }
  ],
  "ResponseMetadata": {
    "HTTPHeaders": {
      "date": "Fri, 26 Jul 2024 14:42:54 GMT",
      "server": "amazon.com",
      "x-amzn-requestid": "BCne5rUZeWfhWmeONuncUz1CkmhRLDUmtQUozDdWqtLBMsdDMNWj"
    },
    "HTTPStatusCode": 200,
    "RequestId": "BCne5rUZeWfhWmeONuncUz1CkmhRLDUmtQUozDdWqtLBMsdDMNWj",
    "RetryAttempts": 0
  }
}

```

As seen above the `sm_client.search` method is not working as expected. It is not returning any of the model groups previously created (even without any filter) while the `sm_client.list_model_package_groups` is returning all of them.
