Enum value "" generating code that does not compile
## Problem statement
An empty value in a string enum results in a name conflict between the generated enum constant and the type.

## Swagger specification
Test case:  fixtures/canary/docker-v1.41/swagger.yaml

## Steps to reproduce
`swagger generate model -f  fixtures/canary/docker-v1.41/swagger.yaml`

## Environment
swagger version: current master
go version: x.x.x
OS:

### Additional contract requirements

- PascalCase conversion of an empty string for use as a generated identifier must yield a non-empty identifier.
- Generating a model from a specification whose string enum contains an empty value must produce code in which the generated enum constant does not share its name with the enum type.
- For the `LocalNodeState` schema in `fixtures/canary/docker-v1.41/swagger.yaml`, the generated enum constants must not include the name `LocalNodeState`.
