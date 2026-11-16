Cloudformation: Response to cloudformation:DescribeStacks missing `ExportName`
# Issue
When running the following code:

```python
with moto.mock_aws():
    response = boto3.client("cloudformation").describe_stacks(StackName=stack_name)
```

the items of `response["Stacks"][0]["Outputs"]` are missing the `ExportName` key, despite the export name being set when creating the CFN stack, and that value being present in real AWS responses.

## Setup
The stack in question was set up like so:
```python
with moto.mock_aws():
    with open(os.path.join(TEST_DIR, "stubs", "stack_template.json"), "r") as file:
        stack_template_str = file.read()

    boto3.client("cloudformation").create_stack(
        StackName=stack_name,
        TemplateBody=stack_template_str,
    )
```

where the `$TEST_DIR/stubs/stack_template.json` is:
```json
{
    "AWSTemplateFormatVersion": "2010-09-09",
    "Transform": "AWS::Serverless-2016-10-31",
    "Description": "Description",
    "Resources": {
        "TestRole": {
            "Type": "AWS::IAM::Role",
            "Properties": {
                "AssumeRolePolicyDocument": {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Action": "sts:AssumeRole",
                            "Principal": {
                                "Service": "lambda.amazonaws.com"
                            }
                        }
                    ]
                }
            }
        }
    },
    "Outputs": {
        "ReadTestObjectsRoleArn": {
            "Description": "ARN of the test role",
            "Value": {
                "Fn::GetAtt": [
                    "TestRole",
                    "Arn"
                ]
            },
            "Export": {
                "Name": {
                    "Fn::Sub": "${AWS::StackName}-test-role-arn"
                }
            }
        }
    }
}

```

# Workaround
[HIDDEN]

```xml
<Outputs>
    {% for output in stack.stack_outputs %}
        <member>
            <OutputKey>{{ output.key }}</OutputKey>
            <OutputValue>{{ output.value }}</OutputValue>
            {% if output.description %}<Description>{{ output.description }}</Description>{% endif %}
        </member>
    {% endfor %}
</Outputs>
```

to:

```xml
<Outputs>
    {% for output in stack.stack_outputs %}
        <member>
            <OutputKey>{{ output.key }}</OutputKey>
            <OutputValue>{{ output.value }}</OutputValue>

            [HIDDEN]

            {% if output.description %}<Description>{{ output.description }}</Description>{% endif %}
        </member>
    {% endfor %}
</Outputs>
```
