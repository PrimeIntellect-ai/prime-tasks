modifies-value-receiver ignores modification to maps and slices
**Describe the bug**
The `modifies-value-receiver` rule is coded to ignore modifications where the object being modified is `map` or `[]foo`.
This is inappropriate: modifying those values is just as wrong as other types of values.
Assignments to a part of the map or slice (i.e. indexing operations) should still be ignored.

**To Reproduce**

Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I modified the test case `modifies-value-receiver.go`, assigning to `items`:
```
package fixtures

type data struct {
	num   int
	key   *string
	items map[string]bool
}

func (this data) vmethod() {
	this.items = make(map[string]bool) // MATCH /suspicious assignment to a by-value method receiver/
	this.items["vmethod"] = true
}
```

3. I run it with the following flags & configuration file:

```shell
revive -config ./defaults.toml ./testdata/modifies-value-receiver.go
```

```toml
# config file
[rule.modifies-value-receiver]
```

**Expected behavior**
I expect a warning on the line assigning to `this.items`.

**Desktop (please complete the following information):**
 - OS: Ubuntu 20.04
 - Version of Go 1.21.1

**Additional context**
The motivating case is here: https://github.com/prometheus/prometheus/pull/13040/files#diff-d9f058bd14a07ebec78d70aaa8d6e8e705bc09086e338b74b12666e7ac121605R1711

### Additional contract requirements

- The warning message for these assignments must contain `suspicious assignment to a by-value method receiver`.
