Prevent nil pointer dereference
Contains*-Assertions panic when a `nil` instead of a string, slice, map etc. is injected.
Minimal example here:

```go
var myMap map[string]interface{} // empty
// try an assertion on nested keys
// which effectively leads to a passing of nil
require.Contains(t, myMap["some-key"], "expected-nested-key") // <-- panic
```

Assertions should be robust against nil-injection and gracefully fail instead of panicking.
