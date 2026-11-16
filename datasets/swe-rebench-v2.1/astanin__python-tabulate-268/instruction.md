SEPARATING_LINE does not work with dataclasses
Using tabulate to print a list of dataclasses when one or more rows is SEPARATING_LINE, produces:

```
  File "....\.venv\lib\site-packages\tabulate\__init__.py", line 1451, in <listcomp>
    rows = [[getattr(row, f) for f in field_names] for row in rows ]
AttributeError: 'str' object has no attribute '<the first attribute of dataclass>'
```

Can be assigned to me, I have a fix.
