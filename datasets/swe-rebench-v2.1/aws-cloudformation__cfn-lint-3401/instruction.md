Errors after upgrading to v1.3
### CloudFormation Lint Version

1.3.3

### What operating system are you using?

macOS

### Describe the bug

after upgrade to v1.3, cfn-lint fails unexpectedly, It generates multiple errors

E1019 {'Ref': 'additionalSubnetBits'} is not of type 'integer' when 'Ref' is resolved when 'Ref' is resolved
E3024 {'Ref': 'additionalSubnetBits'} is not of type 'integer' when 'Ref' is resolved when 'Ref' is resolved
E1020 {'Ref': 'additionalSubnetBits'} is not of type 'integer' when 'Ref' is resolved

There are identical Select functions, one in !If function passes , but the line in !Sub function fails

The code is deployed in CloudFormation, so we know it's valid


### Expected behavior

Code is valid, cfn-lint shouldn't fail

### Reproduction template

```yaml
  AdditionalSubnet1:
    Type: 'AWS::EC2::Subnet'
    Condition: isAdditionalVpc
    DependsOn: AdditionalVpcCIDR
    Properties:
      AvailabilityZone: !If [usesetaz, !Select [0, !Split [",", !Ref physicalazlist]], !Select [0, !GetAZs '']]
      CidrBlock:
        !If
          - isAdditionalCidr1Empty
          - !Select [0, !Cidr [!Ref additionalVpcCidr, 4, !Ref additionalSubnetBits] ]
          - !Ref AdditionalSubnet1Cidr
      MapPublicIpOnLaunch: false
      Tags:
      - Key: Name
        Value: !Sub
        - ${appCode}-${envType}-additional1-${az}-${cidr}
        -
          az: !If [usesetaz, !Select [0, !Split [",", !Ref physicalazlist]], !Select [0, !GetAZs '']]
          cidr: !Select [0, !Cidr [!Ref additionalVpcCidr, 4, !Ref additionalSubnetBits] ]
      VpcId: !Ref vpc
```

### Additional contract requirements

- Running cfn-lint on the template in the reproduction must not report the errors described above, including for the `Fn::Cidr` expression inside the `Fn::Sub` variable map.
- A `Fn::Join` whose list argument is a `Fn::Cidr` call, such as `!Join ['-', !Cidr [!Ref additionalVpcCidr, 4, !Ref additionalSubnetBits]]`, must be accepted and must not be reported as invalid.
- A `Fn::Join` whose second argument is not a list (for example `!Join ['-', 'foo']`) must still be reported as invalid.
