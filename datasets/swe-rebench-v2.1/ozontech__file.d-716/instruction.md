Bug: do_if field op equal matches null value for objects and arrays
**Describe the bug**
Currently do_if field op `equal` allows usage of `null` as a value to check whether the value by the given field is `null` or it does not exist. But it also matches objects and arrays since they are not converted to bytes.

**To Reproduce**
Steps to reproduce the behavior:
1. set action
```yaml
- type: discard
  do_if:
    op: equal
    field: test_field
    values: [null]
```
2. send log `{"test_field":{"key":"val"}}` and `{"test_field":[{"key":"val"}]}`
3. both logs will be discarded.

**Expected behavior**
do_if field op equal should not match object and array with `null`.
