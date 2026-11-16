Is this valid Cloudformation and a cfn-lint bug?
**cfn-lint Version **

0.87.3

Syntax:

// add a pseudo element to array (/null) so we can rely on intrinsic length to pop last element we want
 `Id: !Select [ !Length !Split ["/", !Sub "${AWS::StackName}-v1"], !Split [ "/", !Sub "${AWS::StackName}-v1/null" ] ]`

Response:

E0000 did not find expected ',' or ']'

### Additional contract requirements

- `Fn::Length` is accepted as the index (the first element) of `Fn::Select` when the template uses the `AWS::LanguageExtensions` transform.
- Without the `AWS::LanguageExtensions` transform, `Fn::Length` is not accepted as the index of `Fn::Select`.
- The `!Length !Split [...]` form shown in the report is not valid YAML: a single node cannot carry two tags, so the `E0000` parse error for that exact text is expected. The cfn-lint defect is that `Fn::Length` is rejected as the index of `Fn::Select`; a template that expresses the same intent with valid YAML must lint without errors.
