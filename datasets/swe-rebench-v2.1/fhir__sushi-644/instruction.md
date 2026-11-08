SUSHI reports duplicate "undefined" resource
A user has reported receiving the following message:
> **error** Ignoring FSH definition for undefined since it duplicates existing pre-defined resource. To use the FSH definition, remove the conflicting file from "input". If you do want the FSH definition to be ignored, please comment the definition out to remove this error.

### Additional contract requirements

When a duplicate FSH resource has no URL, its diagnostic must identify the resource using available resource details rather than reporting `undefined`. The duplicate must continue to be ignored and must not be written as a generated resource.
