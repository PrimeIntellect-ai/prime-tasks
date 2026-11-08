No warning for not indented lines in conditions
Given the TypoScript
```typoscript
[globalString = GP:foo = 1]
foo.bar = 3
[global]
```
and the configuration
```yaml
sniffs:
  - class: Indentation
    parameters:
      indentConditions: true
```
the linter completes without warnings. Although line 2 should be indented with 4 spaces.
