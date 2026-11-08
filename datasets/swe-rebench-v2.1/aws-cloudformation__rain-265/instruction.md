The format command does not support yaml anchors when converting to json
YAML anchors are supported by Go, but when trying to convert to JSON with `rain fmt -j`, we get an error:

`yaml: unknown anchor 'fooval' referenced`

```yaml
Resources:
  MyLambda:
    Type: AWS::Lambda::Function
    Properties:
      Code: &code
        ZipFile: "print(\"Hello World!\")\n"
      FunctionName: my-lambda
      Handler: index.lambda_handler
      Role: !ImportValue 'MyLambdaRoleArn'
      Runtime: python3.8
      Tags:
        - Key: foo
          Value: &fooval myval
        - Key: bar
          Value: *fooval
    Metadata:
      Comment: *code
 ```

### Additional contract requirements

- The packaging functions `pkg.File` and `pkg.Template` must resolve YAML anchors and aliases in the template, so that the packaged template can be converted to JSON without the `yaml: unknown anchor ... referenced` error.
- Converting the packaged template to JSON (via `format.String` with `Options{JSON: true}`) must produce valid JSON in which every alias is replaced by the value of its anchor. For the example above, both `Tags` entries have `Value: myval`, and `Metadata.Comment` has the same `ZipFile` value as `Properties.Code`.
