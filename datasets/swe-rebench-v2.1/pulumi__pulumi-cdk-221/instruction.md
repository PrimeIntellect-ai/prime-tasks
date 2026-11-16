Support `FindInMap` intrinsic
## Hello!
<!-- Please leave this section as-is, it's designed to help others in the community know how to interact with our GitHub issues. -->

- Vote on this issue by adding a 👍 reaction
- If you want to implement this feature, comment to let us know (we'll work with you on design, scheduling, etc.)

## Issue details

Right now pulumi-cdk doesn't support the [`FindInMap`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap.html) intrinsic.

For example, this is required by `s3.Bucket` when `autoDeleteObjects: true`.

### Affected area/feature

<!-- If you know the specific area where this feature request would go (e.g. Automation API, the Pulumi Service, the Terraform bridge, etc.), feel free to put that area here.  -->

### Additional contract requirements

When the `Fn::FindInMap` intrinsic cannot be resolved during stack conversion, the converter throws an `Error` whose message contains the following text:

- If the intrinsic is not given exactly three parameters: `Fn::FindInMap requires exactly 3 parameters, got <n>`, where `<n>` is the number of parameters supplied.
- If the stack has no `Mappings` section: `No mappings found in stack`.
- If the referenced mapping name is absent: `Mapping <mappingName> not found in mappings. Available mappings are <mappingNames>`, where `<mappingNames>` is the available mapping names joined by commas.
- If the top-level key is absent: `Key <topLevelKey> not found in mapping <mappingName>. Available keys are <topLevelKeys>`, where `<topLevelKeys>` is the available top-level keys joined by commas.
- If the second-level key is absent: `Key <secondLevelKey> not found in mapping <mappingName>.<topLevelKey>. Available keys are <secondLevelKeys>`, where `<secondLevelKeys>` is the available second-level keys joined by commas.
