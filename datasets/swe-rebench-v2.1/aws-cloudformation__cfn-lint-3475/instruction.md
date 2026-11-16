Outputs on AWS::ServiceCatalog::CloudFormationProvisionedProduct causing errors
### CloudFormation Lint Version

cfn-lint 1.5.0

### What operating system are you using?

Amazon Linux

### Describe the bug

Dynamic values under `Outputs` on `AWS::ServiceCatalog::CloudFormationProvisionedProduct` resource types cause errors.

I tried testing with the vanilla example template from AWS CloudFormation [docs page](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-servicecatalog-cloudformationprovisionedproduct.html#aws-resource-servicecatalog-cloudformationprovisionedproduct--examples) on `AWS::ServiceCatalog::CloudFormationProvisionedProduct`

Running this command:
```
pipenv run cfn-lint --template ./test/success/sc-product.yaml
```

Against the reproduction template gives this error
```
E1010 'Outputs.SCLambdaArn' is not one of ['RecordId', 'CloudformationStackArn', 'Outputs', 'ProvisionedProductId']
test/success/sc-product.yaml:17:41
```

### Expected behavior

!GetAtt on dynamic `Outputs` values should work and not cause E1010 errors.

### Reproduction template

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Serverless Stack
Resources:
  SimpleLambda:
    Type: AWS::ServiceCatalog::CloudFormationProvisionedProduct
    Properties:
      ProductName: Basic Lambda
      ProvisioningArtifactName: '1.0'

  SimpleApiGateway:
    Type: AWS::ServiceCatalog::CloudFormationProvisionedProduct
    Properties:
      ProductName: API Gateway
      ProvisioningArtifactName: '1.0'
      ProvisioningParameters:
        - Key: LambdaArn
          Value: !GetAtt [SimpleLambda, Outputs.SCLambdaArn]
```

### Additional contract requirements

- The `Schema` class in the `cfnlint.schema` module is constructed with the resource schema passed as a keyword argument, for example `Schema(schema=<schema dict>)`.
- A `Schema` instance exposes a public `get_atts` mapping from CloudFormation attribute names (including regex patterns for dynamic attributes) to JSON-pointer strings that locate the attribute definition within the schema.
