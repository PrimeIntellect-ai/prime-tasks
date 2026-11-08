False positive undefined_name with doubly-nested class
```python
def f():
    y = 3

    def inner():

        class Nested:
            classvar = y
```

Produces:

```
Undefined name: y (code: undefined_name)
In nestedcls.py at line 7
   4:     def inner():
   5:
   6:         class Nested:
   7:             classvar = y
                             ^
```

### Additional contract requirements

- When a class is nested inside a function that is nested inside another function, references in the class body to locals from either enclosing function must retain their inferred literal types: `outer_var` must be inferred as `Literal["outer"]` and `inner_var` as `Literal["inner"]`.
