starlarkstruct Freeze() can cause a stack overflow if circular references are involved
If `starlarkstruct.Struct` is exposed to the starlark environment, and one creates a struct with a circular reference, and causes it to be frozen, then there will be a stack overflow.

A module with this Starlark content should reproduce the issue, but I haven't double-checked that it actually does:

```python
def make_struct():
    items = []
    foo = struct(items=items)
    foo.items.append(foo)
    return foo

toplevel = make_struct()
```

A fix for this issue could be done as follows:

```diff
--- a/starlarkstruct/struct.go
+++ b/starlarkstruct/struct.go
@@ -99,6 +99,7 @@ func FromStringDict(constructor starlark
 type Struct struct {
        constructor starlark.Value
        entries     entries // sorted by name
[HIDDEN]
 }

 // Default is the default constructor for structs.
@@ -172,8 +173,11 @@ func (s *Struct) Hash() (uint32, error)
        return x, nil
 }
 func (s *Struct) Freeze() {
-       for _, e := range s.entries {
-               e.value.Freeze()
[HIDDEN]
        }
 }
 ```

### Additional contract requirements

- Freezing a `starlarkstruct.Struct` that participates in a circular reference must terminate without a stack overflow.
- Freezing a `starlarkstruct.Struct` must also freeze the values stored in its entries.
