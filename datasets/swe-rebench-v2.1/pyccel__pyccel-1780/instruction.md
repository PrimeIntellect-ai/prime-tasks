Fix bug with partial templates
## Problem description
Pyccel fails during the semantic stage when trying to accelerate a function which uses a partial template `'T'`, if this not used alone for any of the arguments. That is, Pyccel works correctly if the arguments have types `('T', 'T[:]', 'T[:,:]')`, but fails if they have types `('T[:]', 'T[:,:]')`.

## To reproduce
In this code snippet
``` python
from pyccel.decorators import template

@template(name='T', types=[float, complex])
def mul_sum(a: 'T', v: 'T[:]'):
    return a * v.sum()

@template(name='T', types=[float, complex])
def just_sum(v: 'T[:]'):
    return v.sum()
```
the function `mul_sum` is pyccelized correctly, while the function `just_sum` leads to the error below.

## Error details
Provide the generated code, or the error message:
```bash/fortran/c
ERROR at annotation (semantic) stage
pyccel:
 |fatal [semantic]: test_template.py [8,13]| Undefined variable (T)
```

## Expected behavior
Pyccel should be able to process function `just_sum` with no issues.

## Language
The error happens at the semantic stage, and it is independent of the language.
