cfn-lint is not validating the FindInMap function for Mappings under RegionMap.
### CloudFormation Lint Version

1.16.1

### What operating system are you using?

Mac

### Describe the bug

cfn-lint is not validating the FindInMap function for values under the Mappings section in RegionMap. In the example below, an invalid reference like 'HVM150' should throw an error since it is not defined in either the east or west regions.
Sample Yaml file:

Mappings:
  RegionMap:
    us-east-1:
      HVM64: "ami-0ff8a91507f77f867"
      HVMG2: "ami-0a584ac55a7631c0c"
    us-west-1:
      HVM64: "ami-0bdb828fd58c52235"
      HVMG2: "ami-066ee5fd4a9ef77f1"
Resources:
  myEC2Instance:
    Type: "AWS::EC2::Instance"
    Properties:
      ImageId: !FindInMap
        - RegionMap
        - !Ref 'AWS::Region'
        - HVM150
      InstanceType: t2.micro

### Expected behavior

Validation should work similarly to non-RegionMap mappings.

Example of working validation yaml

Mappings:
  InstanceMap:
    Small:
      "InstanceType12": "t2.micro"
      "KeyName": "my-key-pair-small"
      Resources:
  MyEC2Instance:
    Type: "AWS::EC2::Instance"
    Properties:
      ImageId: "ami-0ff8a91507f77f867"
      InstanceType:
        Fn::FindInMap:
          - InstanceMap
          - Small
          - "InstanceType12"

### Reproduction template

AWSTemplateFormatVersion: '2010-09-09'
Description: AWS CloudFormation Template with FindInMap for non-region section

Mappings:
  RegionMap:
    us-east-1:
      HVM64: "ami-0ff8a91507f77f867"
      HVMG2: "ami-0a584ac55a7631c0c"
    us-west-1:
      HVM64: "ami-0bdb828fd58c52235"
      HVMG2: "ami-066ee5fd4a9ef77f1"
Resources:
  myEC2Instance:
    Type: "AWS::EC2::Instance"
    Properties:
      ImageId: !FindInMap
        - RegionMap
        - !Ref 'AWS::Region'
        - HVM150
      InstanceType: t2.micro

### Additional contract requirements

- Add a public class `Parameter` in module `cfnlint.context.context` that is constructed from a raw CloudFormation parameter definition mapping, for example `Parameter({"Type": "String"})` or `Parameter({"Type": "String", "AllowedValues": ["dev", "test", "prod"]})`. Constructing a `Parameter` with a definition that is not a mapping, or that does not contain a string `Type`, raises `ValueError`.
- Add a `parameters` keyword argument to `cfnlint.context.context.Context` that maps parameter names to `Parameter` objects, alongside its existing `mappings` argument.
