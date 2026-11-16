Support for tags in Amazon API Gateway
# This is a Feature Proposal

## Description

On AWS tags are commonly used for logically associating resources with each other and simplifying billing. Amazon's API Gateway stages support tags now 🎉 . However, those don't seem to be populated by Serverless yet:

![image](https://user-images.githubusercontent.com/1548229/34832452-e0f42dc4-f69e-11e7-8b91-24ed871202d6.png)

Serverless already supports tags for Lambda functions as well as a stack-wide tags (`stackTags`). As an API Gateway stage can only have one set of tags I suggest to automatically assign the `stackTags` to the API Gateway stages during deployment.

### Additional contract requirements

The tags are applied to the API Gateway stage through the compiled CloudFormation template. When `provider.stackTags` has at least one entry, the template must contain a dedicated `AWS::ApiGateway::Stage` resource whose `Properties.Tags` is a list of `{ Key, Value }` entries built from the configured tags, and whose `Properties.StageName` is the provider stage.
