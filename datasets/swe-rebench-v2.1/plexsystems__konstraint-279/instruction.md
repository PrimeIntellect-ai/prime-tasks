Input parameters verification ignores assignment rules
Parameter annotation checker only works for main rego file and doesn't work for imported files.

For example, running `create` on following files produces no errors.
```rego
# src.rego -- annotation @parameter test is missing
package example
import data.lib.foo
violation[{"msg": "msg"}] {
  test = foo.test
  true
}

# lib/foo.rego
package foo
test = input.parameters.test
```

### Additional contract requirements

- Add a function `getRuleParamNames(rules []*ast.Rule) []string` in package `internal/rego` (file `internal/rego/rego.go`), where `ast.Rule` is `github.com/open-policy-agent/opa/ast.Rule`. Given parsed Rego rules, it returns the unique parameter names referenced as `input.parameters.<name>` in those rules, considering both rule bodies and rule values, in order of first occurrence.
