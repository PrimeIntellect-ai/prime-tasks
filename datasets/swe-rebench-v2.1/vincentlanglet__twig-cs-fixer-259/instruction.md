Trailing Comma MultiLine rule breaks multiline strings
### Rule(s) related to or rule(s) missing

TrailingCommaMultiLineRule

### Expected behavior

Any twig function with a multiline string parameter should not trigger a fatal error.

```twig
{{ dump('line1
    line2') }}
```

### Actual behavior

```
KO templates/test/index.html
 ------- ------------------------------------------------------------------------------------
  FATAL   >>   | Unable to fix file: Too many iteration while trying to fix file.
 ------- ------------------------------------------------------------------------------------
  ERROR   9    |     {{ dump('line1
          10   |     line2') }}
          >>   | Multi-line arrays, objects and parameters lists should have trailing comma.
          11   | </body>
 ------- ------------------------------------------------------------------------------------
```
