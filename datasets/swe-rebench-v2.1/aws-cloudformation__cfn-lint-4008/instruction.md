E8001 "_" in Condition name does not match regex pattern
### CloudFormation Lint Version

1.29.0

### What operating system are you using?

ubuntu

### Describe the bug

A Condition with an "_" in the name violates the cfn-lint reported regex pattern  '^[a-zA-Z0-9&]{1,255}$'



### Expected behavior

Adjust the cfn-lint expected regex pattern to accept "_" also since cloudformation has no issues with this


### Reproduction template

Conditions:
      DeployAz_A:
        Fn::Equals:
          - "true"
          - "false"
