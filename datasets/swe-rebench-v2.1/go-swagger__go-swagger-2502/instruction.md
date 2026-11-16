0.26.0 - Enum constants are not unique for some special characters
## Problem statement

Same issue as in #2050; however the fix in #2051 did not cover the characters `=` `*`, and `/`, and I am seeing the same issue where there are multiple generated constants using the same name. I am using go-swagger v0.26.0.

Example generated client code:

```golang
const (

	// ModificationSourceOperation captures enum value "="
	ModificationSourceOperation string = "="

	// ModificationSourceOperationPlus captures enum value "+"
	ModificationSourceOperationPlus string = "+"

	// ModificationSourceOperationDash captures enum value "-"
	ModificationSourceOperationDash string = "-"

	// ModificationSourceOperation captures enum value "*"
	ModificationSourceOperation string = "*"

	// ModificationSourceOperation captures enum value "/"
	ModificationSourceOperation string = "/"
)
```

swagger.json for reproducing the bug:

```json
{
  "definitions": {
    "ModificationSource": {
      "type": "object",
      "properties": {
        "operation": {
          "type": "string",
          "enum": ["=", "+", "-", "*", "/"]
        }
      }
    }
  }
}
```

### Additional contract requirements

- When a single-character enum value is converted to a PascalCase name, `*` must produce `Asterisk`, `/` must produce `ForwardSlash`, and `=` must produce `EqualSign`.
