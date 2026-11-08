[PARSE BUG]: operator overloading with *
### Problem description

I got this parse error `parse error evaluating '*': unexpected '*', expected '('` when parsing some c++ code.
I think this is a problem with operator overloading over the `*` operator.

### C++ code that can't be parsed correctly (please double-check that https://robotpy.github.io/cxxheaderparser/ has the same error)

```text
operator const native_handle_t*() const
{
    return mHandle;
}
```

### Additional contract requirements

The parser must accept the conversion-operator definition shown above with its const pointer target (`const native_handle_t*`), const-qualified conversion function, and function body.
