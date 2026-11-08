cfn-lint v1 does not warn about missing mapping keys
### CloudFormation Lint Version

1.3.3 & git (b0782f87c)

### What operating system are you using?

Mac

### Describe the bug

cfn-lint v1 (1.3.3) does not warn about missing mapping keys.

This was first noticed with missing second level key, but it applies to both first and second level.

### Expected behavior

cfn-lint 0.87.7 would warn:
```
W1011 FindInMap second key "MissingName" doesn't exist in map "Map" under "Key" at Resources/Bucket/Properties/BucketName/Fn::FindInMap
map.yaml:14:11
```

I would actually expect this to be `W7xxx` or even `E7xxx`, but I'll be happy with anything other than silence 😄

### Reproduction template

```
AWSTemplateFormatVersion: '2010-09-09'
Mappings:
  Map:
    Key:
      Name: "unused"
Resources:
  Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName:
        Fn::FindInMap:
        - "Map"
        - "Key"
        - "MissingName"
```

### Additional contract requirements

- For an invalid `Fn::FindInMap` map key, the validation error for `{"Fn::FindInMap": ["A", "C", "B"]}` must have message `"'C' is not one of ['B']"`, path `deque(["Fn::FindInMap", 1])`, and schema path `deque([])`.
- For an invalid `Fn::FindInMap` second-level map key, the validation error for `{"Fn::FindInMap": ["A", "B", "Missing"]}` must have message `"'Missing' is not one of ['C']"`, path `deque(["Fn::FindInMap", 2])`, and schema path `deque([])`.
- `CfnTemplateValidator.resolve_value(instance)` in module `cfnlint.jsonschema.validators` returns a lazy iterator of resolution results. Each result is a tuple `(resolved_value, validator, error)` where `resolved_value` is the resolved value or `None`, `validator` is the `Validator` instance that performed the resolution, and `error` is `None` or a `ValidationError` describing why the resolution failed. For a value that has a registered resolver, at least one result is produced.
- `ResolutionResult` and `Validator` are importable from module `cfnlint.jsonschema._resolvers_cfn`.
- A validator exposes a `fn_resolvers` mapping from function names to resolver callables, which can be supplied when constructing the validator.
- For `{"Ref": "fail"}` where the resolver returns `ValidationError("Foo")`, the yielded error equals `ValidationError("Foo", path=deque(["Ref"]))`.
