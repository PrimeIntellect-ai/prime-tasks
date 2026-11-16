SageMaker Search method for Model Groups not working with `Contains` filter
# Environment Information

Python Version: 3.8.12
- boto3 == 1.24.4
- pytest == 8.3.2
- moto == 5.0.13


# Documentation Reference
According to the [latest moto documentation](https://docs.getmoto.org/en/latest/docs/services/sagemaker.html) for sagemaker implemented services, the following methods are implemented:

- [X] create_model_package_group
- [X] list_model_package_groups
- [X] search

# Problem Description
I am currently using moto test the retrieval of model package groups based on certain tags. I created some model groups for testing, but when calling the method sagemaker_client.search with a `contains`name filter all the model groups were returned without any additional filter. I also called the list_model_groups method to show all the model groups that were previously created, for comparison.

## Minimal Example

**search_model_group.py**

```python
import boto3

class ModelGroupFinder:
    def __init__(self):
        self.sm_client = boto3.client('sagemaker')

    class ModelGroupFinder:
    def __init__(self):
        self.sm_client = boto3.client('sagemaker')

    def get_model_groups_with_search_method(self):
        search_results = self.sm_client.search(
            Resource='ModelPackageGroup',
            SearchExpression={
                'Filters': [{
                    'Name': 'ModelPackageGroupName',
                    'Operator': 'Contains',
                    'Value': '_DEV'}]}
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

## Sagemaker Search Function:

```
example/test_model_groups.py Sagemaker Search Function:
{'ResponseMetadata': {'HTTPHeaders': {'date': 'Tue, 20 Aug 2024 10:55:16 GMT',
                                      'server': 'amazon.com',
                                      'x-amzn-requestid': 'ANTahPltMIovDSarJhsDo4KQcfSn4cZr27RrV2vUW5PemHos0ylv'},
                      'HTTPStatusCode': 200,
                      'RequestId': 'ANTahPltMIovDSarJhsDo4KQcfSn4cZr27RrV2vUW5PemHos0ylv',
                      'RetryAttempts': 0},
 'Results': [{'ModelPackageGroup': {'CreationTime': datetime.datetime(2024, 8, 20, 13, 55, 16),
                                    'ModelPackageGroupArn': 'arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test_DEV',
                                    'ModelPackageGroupDescription': 'Model '
                                                                    'group in '
                                                                    'DEV '
                                                                    'environment.',
                                    'ModelPackageGroupName': 'model-test_DEV',
                                    'ModelPackageGroupStatus': 'Completed',
                                    'Tags': [{'Key': 'RegisteredBySourceRoleArn',
                                              'Value': 'arn:aws:iam::123456789012:role/DSSourceRole'}]}},
             {'ModelPackageGroup': {'CreationTime': datetime.datetime(2024, 8, 20, 13, 55, 16),
                                    'ModelPackageGroupArn': 'arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test_PROD',
                                    'ModelPackageGroupDescription': 'Model '
                                                                    'group in '
                                                                    'PROD '
                                                                    'environment.',
                                    'ModelPackageGroupName': 'model-test_PROD',
                                    'ModelPackageGroupStatus': 'Completed',
                                    'Tags': [{'Key': 'RegisteredBySourceRoleArn',
                                              'Value': 'arn:aws:iam::123456789012:role/DSSourceRole'}]}},
             {'ModelPackageGroup': {'CreationTime': datetime.datetime(2024, 8, 20, 13, 55, 16),
                                    'ModelPackageGroupArn': 'arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model',
                                    'ModelPackageGroupDescription': 'Model '
                                                                    'group in '
                                                                    'other '
                                                                    'environment.',
                                    'ModelPackageGroupName': 'model',
                                    'ModelPackageGroupStatus': 'Completed',
                                    'Tags': [{'Key': 'RegisteredBySourceRoleArn',
                                              'Value': 'arn:aws:iam::123456789012:role/OtherSourceRole'}]}}]}
```

## Sagemaker List Model Package Groups function

```
{'ModelPackageGroupSummaryList': [{'CreationTime': datetime.datetime(2024, 8, 20, 13, 55, 16, 150531, tzinfo=tzutc()),
                                   'ModelPackageGroupArn': 'arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test_DEV',
                                   'ModelPackageGroupDescription': 'Model '
                                                                   'group in '
                                                                   'DEV '
                                                                   'environment.',
                                   'ModelPackageGroupName': 'model-test_DEV',
                                   'ModelPackageGroupStatus': 'Completed'},
                                  {'CreationTime': datetime.datetime(2024, 8, 20, 13, 55, 16, 151405, tzinfo=tzutc()),
                                   'ModelPackageGroupArn': 'arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model-test_PROD',
                                   'ModelPackageGroupDescription': 'Model '
                                                                   'group in '
                                                                   'PROD '
                                                                   'environment.',
                                   'ModelPackageGroupName': 'model-test_PROD',
                                   'ModelPackageGroupStatus': 'Completed'},
                                  {'CreationTime': datetime.datetime(2024, 8, 20, 13, 55, 16, 152038, tzinfo=tzutc()),
                                   'ModelPackageGroupArn': 'arn:aws:sagemaker:us-east-1:123456789012:model-package-group/model',
                                   'ModelPackageGroupDescription': 'Model '
                                                                   'group in '
                                                                   'other '
                                                                   'environment.',
                                   'ModelPackageGroupName': 'model',
                                   'ModelPackageGroupStatus': 'Completed'}],
 'ResponseMetadata': {'HTTPHeaders': {'date': 'Tue, 20 Aug 2024 10:55:16 GMT',
                                      'server': 'amazon.com',
                                      'x-amzn-requestid': 'BHGbElTsvY73Gv9RMp0Orw7O90dE2PieQAgjcL2wFofdOmu3OlRx'},
                      'HTTPStatusCode': 200,
                      'RequestId': 'BHGbElTsvY73Gv9RMp0Orw7O90dE2PieQAgjcL2wFofdOmu3OlRx',
                      'RetryAttempts': 0}}
```


As seen above the sm_client.search method is not working as expected. It is returning all the model groups instead of only filtering the model groups names containing the substring '_DEV'.
