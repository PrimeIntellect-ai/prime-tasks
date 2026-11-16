add-constant suggests invalid fix of replacing struct tags with string constants for anonymous structs
**Describe the bug**

revive incorrectly suggests replacing duplicated struct tags with string constants, for tags found in anonymous struct literals.

Example file to reproduce:

```
package test

func x() {
	a := struct {
		X int `json:"x"`
	}{}

	b := struct {
		X int `json:"x"`
	}{}

	c := struct {
		X int `json:"x"`
	}{}

	_, _, _ = a, b, c
}
```

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags & configuration file:

```shell
# flags

revive -config config.toml .
```

Output:

```
test.go:13:9: string literal `json:"x"` appears, at least, 3 times, create a named constant for it
```

```toml
[rule.add-constant]
```

**Expected behavior**
Struct tags in anonymous struct literals should be ignored by this rule, as they are for struct type definitions.
