AWS::Serverless::StateMachine.DefinitionUri support for local files
*cfn-lint version: 0.32.1*

*Description of issue.*

The recent release of SAM support for Step Functions has added the ability to use a non-S3 URL for the [`DefinitionUri`](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-resource-statemachine.html#sam-statemachine-definitionuri) in order to reference local files that get included during a deploy. The linter is currently throwing an error for all non-S3 values, though.

```
[cfn-lint] E0001: Error transforming template: Resource with id [StateMachine] is invalid. 'DefinitionUri' is not a valid S3 Uri of the form 's3://bucket/key' with optional versionId query parameter.
```
