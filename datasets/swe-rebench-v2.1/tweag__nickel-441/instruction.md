`default` values and contracts don’t compose properly
**Describe the bug**

When a value `bar` has a contract and a default value, and its default value itself has both a contract and a default value, then the default of the default value will be ignored, and only its contract will be applied.

**To Reproduce**

Evaluating

```
let
  myContract = { x | Str }
in
{
  foo | #myContract | default = { x = "From foo" },
  bar | #{..} | default = foo
}
```

results in

```
error: empty metavalue
  ┌─ /tmp/tmp.eYEzU3ur1v/test.ncl:4:18
  │
4 │   myContract = { x | Str }
  │                  ^^^^^^^ here
```

rather than the expected

```
{
  "bar": {
    "x": "From foo"
  },
  "foo": {
    "x": "From foo"
  }
}
```

Everything works fine if `bar` either doesn’t have a contract or has a plain type annotation (`bar | { x : Str } | default = foo`).


**Environment**
 - OS name + version: NixOS 21.05
 - Version of the code: 8ce9a90

/cc @yannham
