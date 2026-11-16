Invalid Aliases when using SSM dynamic references
### CloudFormation Lint Version

0.83.0

### What operating system are you using?

Mac

### Describe the bug

When using a dynamic reference to resolve the Alias domain, cfn-lint fails indicating it's an invalid alias. [HIDDEN]

A workaround would be to use "!Sub" which apparently is ignored already (`FUNCTIONS`). [HIDDEN]

### Expected behavior

E3013 shouldn't be informed, since there's no way to validate the dynamic-reference value from cfn-lint perspective (?)

### Reproduction template

```
CloudFront:
        Type: AWS::CloudFront::Distribution
        Properties:
            DistributionConfig:
                Enabled: true
                Aliases:
                    - "{{resolve:ssm:/env/fqdns/certifier}}"
                DefaultRootObject: index.html
```

### Additional contract requirements

- Do not report E3013 solely because an unresolved dynamic reference used as a CloudFront Alias does not match the Alias format; cfn-lint cannot validate the resolved value.
