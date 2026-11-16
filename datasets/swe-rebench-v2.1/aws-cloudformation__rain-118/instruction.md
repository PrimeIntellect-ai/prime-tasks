"semantic difference after formatting" for FindInMap
`rain` seems to be throwing "semantic difference after formatting" error for valid YAML template.

Example template:
```
---
AWSTemplateFormatVersion: '2010-09-09'

Description: Reproduce "semantic difference after formatting" error

Parameters:
  EnvironmentParam:
    Default: dev
    Type: String
    AllowedValues:
      - dev
      - prod

Mappings:
  EnvironmentMap:
    MappedParam:
      dev: my-dev-topic
      prod: my-prod-topic

Resources:
  Topic:
    Type: AWS::SNS::Topic
    Properties:
      TopicName: !FindInMap [ EnvironmentMap, MappedParam, !Ref EnvironmentParam ]
```

Command:
```
$ rain fmt --json example.yml
semantic difference after formatting:
(|) Resources:
(|)   Topic:
(|)     Properties:
(>)       TopicName:
(>)         - EnvironmentMap
(>)         - MappedParam
(>)         - Ref: EnvironmentParam
```

Version:
```
$ rain --version
Rain v1.3.3 linux/amd64
```

`cfn-lint` is happy with the template:
```
$ cfn-lint --info example.yml
2023-04-04 09:05:55,695 - cfnlint.runner - INFO - Run scan of template example.yml
$ cfn-lint --version
cfn-lint 0.75.1
```

### Additional contract requirements

- When a template is formatted as JSON (`rain fmt --json`), the `Fn::GetAtt`
  intrinsic must be rendered as a two-element JSON array holding the logical
  resource name and the attribute name, for example:

  ```json
  "Fn::GetAtt": ["Bucket1", "Arn"]
  ```
