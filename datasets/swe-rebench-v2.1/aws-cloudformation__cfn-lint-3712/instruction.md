E8005 - False positive in Rules section, thinks !Contains is not returning a boolean
### CloudFormation Lint Version

1.15.0

### What operating system are you using?

Fedora

### Describe the bug

We have a rule which has a RuleCondition which has

!Not [ !Contains [ [ <list of items ], !Ref SomeParameter ] ]

This is now returning an error

E8005 {'Fn::Contains': [ [<list of items> ], {'Ref': 'SomeParameter'}]} is not of type boolean

This was working against cfn-lint 1.14.2

### Expected behavior

Rule should not cause E8005 error

### Reproduction template

```
AWSTemplateFormatVersion: 2010-09-09

Description: FalsePositive-E8005
Parameters:

    ElasticsearchSize:
        Description: This value is NOT required when using an instance type which uses instance store storage (r6gd or i3)
        # This must be a string as it can be empty in some scenarios (which makes it an invalid number...
        Type: String

    ElasticsearchInstanceType:
        Description: The ES data instance type
        Type: String
        Default: r5.large.elasticsearch
        AllowedValues: [
            m5.large.elasticsearch, m5.xlarge.elasticsearch, m5.2xlarge.elasticsearch, m5.4xlarge.elasticsearch, m5.12xlarge.elasticsearch,
            r5.large.elasticsearch, r5.xlarge.elasticsearch, r5.2xlarge.elasticsearch, r5.4xlarge.elasticsearch, r5.8xlarge.elasticsearch, r5.16xlarge.elasticsearch,
            c5.large.elasticsearch, c5.xlarge.elasticsearch, c5.2xlarge.elasticsearch, c5.4xlarge.elasticsearch, c5.9xlarge.elasticsearch, c5.18xlarge.elasticsearch,
            c6g.large.elasticsearch, c6g.xlarge.elasticsearch, c6g.2xlarge.elasticsearch, c6g.4xlarge.elasticsearch, c6g.8xlarge.elasticsearch, c6g.12xlarge.elasticsearch,
            r6gd.large.elasticsearch, r6gd.xlarge.elasticsearch, r6gd.2xlarge.elasticsearch, r6gd.4xlarge.elasticsearch, r6gd.8xlarge.elasticsearch, r6gd.16xlarge.elasticsearch,
            i3.large.elasticsearch, i3.xlarge.elasticsearch, i3.2xlarge.elasticsearch, i3.4xlarge.elasticsearch, i3.8xlarge.elasticsearch, i3.16xlarge.elasticsearch
        ]
        ConstraintDescription: The elasticache data instance type must be of a type which supports encryption at rest

Rules:

        #this rule passes
        ESInstanceStorageInstanceStore:
            RuleCondition: !Contains [ [
                r6gd.large.elasticsearch, r6gd.xlarge.elasticsearch, r6gd.2xlarge.elasticsearch, r6gd.4xlarge.elasticsearch, r6gd.8xlarge.elasticsearch, r6gd.16xlarge.elasticsearch,
                i3.large.elasticsearch, i3.xlarge.elasticsearch, i3.2xlarge.elasticsearch, i3.4xlarge.elasticsearch, i3.8xlarge.elasticsearch, i3.16xlarge.elasticsearch
            ], !Ref ElasticsearchInstanceType ]
            Assertions:
              - Assert: !Equals [ !Ref ElasticsearchSize, '' ]
                AssertDescription: "The Elasticsearch EBS size parameter must NOT be set when the instance type is r6gd or i3"

        #This rule fails as it thinks !Contains is not returning a boolean
        ESInstanceStorageEBS:
            RuleCondition: !Not [ !Contains [ [
                r6gd.large.elasticsearch, r6gd.xlarge.elasticsearch, r6gd.2xlarge.elasticsearch, r6gd.4xlarge.elasticsearch, r6gd.8xlarge.elasticsearch, r6gd.16xlarge.elasticsearch,
                i3.large.elasticsearch, i3.xlarge.elasticsearch, i3.2xlarge.elasticsearch, i3.4xlarge.elasticsearch, i3.8xlarge.elasticsearch, i3.16xlarge.elasticsearch
            ], !Ref ElasticsearchInstanceType ] ]
            Assertions:
              - Assert: !Not [ !Equals [ !Ref ElasticsearchSize, '' ] ]
                AssertDescription: "The Elasticsearch EBS size parameter must be set for this instance type"

Resources:

    Resource:
        Type: AWS::IAM::Role
        Properties:
            RoleName: 'Resource'
            AssumeRolePolicyDocument:
                Version: '2012-10-17'
                Statement:
                  - Effect: 'Allow'
                    Principal:
                        Service:
                          - events.amazonaws.com
                          - scheduler.amazonaws.com
                    Action:
                      - 'sts:AssumeRole'

```
