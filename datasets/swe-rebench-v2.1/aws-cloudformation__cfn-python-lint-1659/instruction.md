AWS::ServiceCatalog::CloudFormationProvisionedProduct.Outputs
In July 2020, support for retrieving the outputs of provisioned Service Catalog products [was added to CloudFormation](https://aws.amazon.com/blogs/mt/how-to-launch-secure-and-governed-aws-resources-with-aws-cloudformation-and-aws-service-catalog/).

Given the following example template:

```yaml
AWSTemplateFormatVersion: '2010-09-09'

Resources:
  ProvisionedProduct:
    Type: AWS::ServiceCatalog::CloudFormationProvisionedProduct
    Properties:
      ProductName: example
      ProvisioningArtifactName: v1

Outputs:
  OutputValue:
    Value: !GetAtt ProvisionedProduct.Outputs.Example

  OutputSub:
    Value: !Sub '${ProvisionedProduct.Outputs.Example}-example'
```

The following linting errors are output when using cfn-lint 0.35.0:

```
E1010 Invalid GetAtt ProvisionedProduct.Outputs.Example for resource OutputValue
example.yml:12:5

E1019 Parameter ProvisionedProduct.Outputs.Example for Fn::Sub not found at Outputs/OutputSub/Value/Fn::Sub
example.yml:15:5
```

Access to these outputs using `!GetAtt` is documented in the announcement of this functionality (e.g. `!GetAtt ApacheALB.Outputs.ALBTarget`). Additionally the example template given above works correctly when deployed.

`Output` is documented in the [AWS::ServiceCatalog::CloudFormationProvisionedProduct return values](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-servicecatalog-cloudformationprovisionedproduct.html#aws-resource-servicecatalog-cloudformationprovisionedproduct-return-values) and appears to already be defined within cfn-lint CloudSpecs as a `Map` type.

I believe that this a false positive and am not aware of any alternative syntax to access these outputs (e.g. `!FindInMap` doesn't appear to be usable in this instance).
