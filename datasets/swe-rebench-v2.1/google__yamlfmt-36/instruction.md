yamlfmt insert blank line between commented line
I have the following YAML:

```
---
Resources:
  ElasticBeanstalk:
    Type: AWS::CloudFormation::Stack
    Properties:
      #NotificationARNs:
      #  - String
      #Parameters:
      #  Key : Value
      #Tags:
      #  - Tag
      TemplateURL: https://examplebucket.s3.ap-southeast-1.amazonaws.com/example-file.json
      TimeoutInMinutes: 5
```

after formatting, each commented line will have a blank line inserted, becoming:

```
Resources:
  ElasticBeanstalk:
    Type: AWS::CloudFormation::Stack
    Properties:
      #NotificationARNs:

      #  - String

      #Parameters:

      #  Key : Value

      #Tags:

      #  - Tag
      TemplateURL: https://examplebucket.s3.ap-southeast-1.amazonaws.com/example-file.json
      TimeoutInMinutes: 5
```

I don't see any option to configure the formatter so that it does not include a blank line after each comment.

Thank you.

### Additional contract requirements

- The formatter configuration accepts a `line_ending` key. Setting it to `crlf` makes the formatter handle YAML whose lines end with CRLF (`\r\n`).
- With `line_ending` set to `crlf`, formatting YAML that contains commented lines must not insert blank lines after those comments.
- With `line_ending` set to `crlf`, every comment in the input must still be present in the formatted output.
- With `line_ending` set to `crlf`, the formatted output must have the same YAML content as the input; only the line-ending bytes may differ.
