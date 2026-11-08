Comment on the last line of a FSH file causes an error
If the last line of a FSH file is a comment or if the last line ends with an inline comment, the following error is reported:

`error: extraneous input '//' expecting {<EOF>, KW_ALIAS, KW_PROFILE, KW_EXTENSION, KW_INSTANCE, KW_INVARIANT, KW_VALUESET, KW_CODESYSTEM}`

This may be related to the fix for #130 because I did not see this issue prior the the PR that addressed that bug.

Example FSH files that will report that error:

```
Instance: Example
InstanceOf: Patient
// Comment
```

```
Instance: Example
InstanceOf: Patient // Comment
```
