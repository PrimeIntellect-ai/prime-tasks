Can't compare strings
### Describe the bug
Strings cannot be compared as the comparison triggers non-implemented `ContainerType` methods.

### To Reproduce
Provide code to reproduce the behaviour:
```python
ef f():
    option = 'hello'
    if option == 'do this':
        return 1.0
    else:
        return 2.0
```

### Error details
Provide the generated code, or the error message:
```bash/fortran/c
AttributeError: 'PrimitiveCharacterType' object has no attribute 'switch_basic_type'
```

### Expected behaviour
String comparison should work like integer comparison or floating point comparison.

### Language
Semantic error implies all languages.

### Proposed Solution
[HIDDEN]

### Additional context
Related to #2194

### Additional contract requirements

- String equality (`==`) and inequality (`!=`) comparisons must be accepted and produce results equivalent to Python string comparisons.
