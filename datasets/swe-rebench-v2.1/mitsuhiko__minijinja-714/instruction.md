Macro variables' declared-ness is leaking to outer scope
## Description

Variables that share a name with a macro's variables are not considered undeclared, despite them being unbound.

## Reproduction steps

```python
from minijinja import Environment

env = Environment()

vars = env.undeclared_variables_in_str("""
{%- macro bar(a) -%}
    -{{a}}-
{%- endmacro- %}
{{a}}
""")

print(vars)
--> set()  # Expected {'a'}
```

Additional helpful information:

- Version of minijinja: 2.7.0
- Version of rustc: N/A
- Operating system and version: MacOS M1 Max Seqouia

## What did you expect

`a` is unbound, and is indeed a free variable. It's expected that `undeclared_variables_in_str` will return a as an undeclared variable
