Major change in 1.5.1 removes empty lines after class definitions
I updated to docformatter 1.5.1 from 1.5.0 expecting no major changes to take place. However, I found that running `docformatter` removes *all* empty lines following class definitions, *even when there is no docstring present*.

I'm not sure if this is intentional, but I expected docformatter to only modify places where there is a docstring present.

(I ran into this face-first because Django generates its migration files with an empty line after class definition, so a patch version upgrade resulted in `171 files changed, 113 insertions(+), 286 deletions(-)` for me. Half of that is this issue, the other half that apparently the max line length was slightly shortened?)

### Reproduction:

Format this file with `docformatter==1.5.0` and `docformatter==1.5.1`:

```python
class Test:

    default = True
```

1.5.0 will leave the file alone, while 1.5.1 will output

```
--- before/test.py
+++ after/test.py
@@ -1,3 +1,2 @@
 class Test:
-
     default = True
```

This change appears to be related to #130.

### Additional contract requirements

- When a class has a docstring, remove any blank line between the class definition and its docstring.
