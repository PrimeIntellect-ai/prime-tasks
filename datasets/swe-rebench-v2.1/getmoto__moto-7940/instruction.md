Moto doesn't support mock cloudformation which has a lambda resource deployed as container
## Reporting Bugs

**how to reproduce the issue**
```
import os
import pytest
import json
import boto3
from moto import mock_aws
from unittest.mock import Mock

dummy_template = {
    "AWSTemplateFormatVersion": "2010-09-09",
    "Resources": {
        "LambdaFunction": {
            "Type": "AWS::Lambda::Function",
            "Properties": {
                "FunctionName": "ContainerLambdaFunction",
                "Role": "dummy-role-arn",
                "Code": {
                    "ImageUri": "123456789012.dkr.ecr.us-west-2.amazonaws.com/my-lambda-container:latest"
                    },
                "PackageType": "Image",
                "MemorySize": 128,
                "Timeout": 30
            }
        }
    }
}
dummy_template_json = json.dumps(dummy_template)

@pytest.fixture(scope="function")
def aws_credentials():
    print('Setting up AWS credentials for mocked boto3 clients...')
    os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
    os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
    os.environ['AWS_SECURITY_TOKEN'] = 'testing'
    os.environ['AWS_SESSION_TOKEN'] = 'testing'
    os.environ['AWS_DEFAULT_REGION'] = 'eu-west-1'


@pytest.fixture(scope="function")
def cloudformation(aws_credentials):
    with mock_aws():
        yield boto3.client('cloudformation', region_name='us-west-2')

def test_lambda_with_container_deployment(cloudformation):
    cloudformation.create_stack(StackName='dummy-stack-name', TemplateBody=dummy_template_json)

```

**what you expected to happen**: test not fail
**what actually happens**
```
        # required
        spec = {
            "Code": properties["Code"],
            "FunctionName": resource_name,
>           "Handler": properties["Handler"],
            "Role": properties["Role"],
            "Runtime": properties["Runtime"],
        }
E       KeyError: 'Handler'
```
Error was thrown from [this line](https://github.com/getmoto/moto/blob/master/moto/awslambda/models.py#L1153)

**moto version: moto[all]==5.0.11**
