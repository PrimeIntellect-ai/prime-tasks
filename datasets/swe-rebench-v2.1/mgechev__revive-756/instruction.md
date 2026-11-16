[rule.add-constant] add ''ignoreFuncs' to exclude constants in functions
**Is your feature request related to a problem? Please describe.**
I want to add 'ignoreFuncs' in configuration
to have a possibility to exclude constants in functions

```
[rule.add-constant]
  arguments = [{'ignoreFuncs="println,os.Chmod"}]
```

**Describe the solution you'd like**
I want to create PR with changes, which add this feature
