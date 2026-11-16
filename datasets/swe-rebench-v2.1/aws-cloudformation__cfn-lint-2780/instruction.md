E0002: Unknown exception while processing rule E1024: 'list' object has no attribute 'path'
### CloudFormation Lint Version

cfn-lint 0.77.10

### What operating system are you using?

Mac

### Describe the bug

When validation checks run on a the Cidr function `!Cidr [ ipBlock, count, cidrBits ]`, the count and cidrBits doesn't validate more complex functions like the `!If` in the example.

### Expected behavior

Doesn't throw unknown exception

### Reproduction template

```yaml
PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs ""]
      CidrBlock: !If
        - defineYourOwnSubnetCIDR
        - !Ref FirstTierSubnet1CIDR
        - !Select
          - 0
          - !Cidr
            - 10.0.0.0/24
            - !If [3AZ, 16, 8]
            - 4
```
