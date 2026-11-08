JSON encoding of floats does not match the documentation
Hello,

The [documentation](https://pkg.go.dev/go.starlark.net/lib/json) states that:

> Starlark float values are encoded using decimal point notation, even if the value is an integer.

This suggests that float(1) should be encoded as 1.0, similar to Python:

```python
>>> import json
>>> json.dumps([1.0])
"[1.0]"
```

[HIDDEN] Hence:

```starlark
>>> json.encode([1.0])
"[1]"
```
It appears that "encoding/json" module in Go [exhibits the same behavior](https://stackoverflow.com/questions/20099328/does-go-correctly-marshal-float64-to-json).

Even a comment in the Starlark source code misleadingly states that a float representation "always contains a decimal point":
https://github.com/google/starlark-go/blob/1207426daebd7ea8eb86b8d917a344a72cc5167b/lib/json/json.go#L150

In my opinion, since Starlark tries to be similar to Python, the JSON serialization should behave the same way and preserve the information about the floating-point type. I don't expect that changing the formatting will break existing code, but even so the current implementation will definitely lead to bugs. However, in case you decide not to change anything here, please update the documentation accordingly.

Thank you!

### Additional contract requirements

- `json.encode` of a Starlark float with an integer value must produce decimal point notation, as the documentation states. For example, `json.encode(float(1))` returns `1.0`, and `json.encode([float(-7), float(42)])` returns `[-7.0,42.0]`. Decoding the output with `json.decode` must give back a float equal to the original value.
- Updating the documentation to describe the integer-looking output is not an acceptable resolution; the encoding itself must use decimal point notation for these values.
