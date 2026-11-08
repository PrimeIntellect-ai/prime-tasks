[PARSE BUG]:  function with trailing return type
### Problem description

**function with trailing return type having implementation won't parse**
parse error evaluating '{': unexpected '{'
auto test() -> void
{
}

the declaration parses correctly
auto test2() -> void;

ordinary return type having implementation parses
void test3()
{
}

I double checked  https://robotpy.github.io/cxxheaderparser/ has the same error

### C++ code that can't be parsed correctly (please double-check that https://robotpy.github.io/cxxheaderparser/ has the same error)

```text
auto test() -> void
{
}
```

### Additional contract requirements

Function definitions using a trailing return type must be parsed when their bodies contain statements; the declared return type and the presence of the body must be retained.
