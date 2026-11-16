E1152 and dynamic parameters
### CloudFormation Lint Version

cfn_lint-1.3.0-py3-none-any

### What operating system are you using?

Alpine in docker (python:3.12-alpine / python@sha256:a982997504b8ec596f553d78f4de4b961bbdf5254e0177f6e99bb34f4ef16f95)

### Describe the bug

The linter complains that a [dynamic parameter](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/dynamic-references.html) is not a valid value for the `LaunchTemplateData.ImageId` field in `AWS::EC2::LaunchTemplate`.

The error message is:
```
E1152 'resolve:ssm:/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id' is not a 'AWS::EC2::Image.Id'
```

### Expected behavior

cfn-lint should not produce errors for this template

### Reproduction template

```yaml
AWSTemplateFormatVersion: "2010-09-09"

Resources:
  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateData:
        ImageId: resolve:ssm:/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id
```

### Additional contract requirements

- The `Path` class in module `cfnlint.context` accepts `path` and `cfn_path` (each a `collections.deque`) and stores the provided values.
- A `Path` instance exposes a `cfn_path_string` property whose value is the `/`-joined string of its `cfn_path` entries.
- The `ImageId` format check must accept a `resolve:ssm:` value when the value's `cfn_path` is the path for the `ImageId` property of `LaunchTemplateData` on an `AWS::EC2::LaunchTemplate` resource, and must reject `resolve:ssm:` values at any other `cfn_path`.
