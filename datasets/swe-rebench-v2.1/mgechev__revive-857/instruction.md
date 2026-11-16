Glob/regex file excludes at rule level
Where are different policies for some files.
For example we never treat `add-constant` as warning in `*_test.go` files.
For now - we cannot express excludes at rule level - just at global level.

Suggested to add `exclude : []string` for configuration and `exclude: []*regexp.Regex` inside.

To distinguish between regexes and strings we could use `~` prefix for regexes:

```
# revive toml
# bettter to treat Exclude as common thing for all rules
[rule.add-constant]
    Exclude = [ "pkg/x/some.go" , "~_test.go$" ] # first is direct file name, second is regex
    Arguments = [
          {
             allowInts="-1,0,1,2",
             allowStrs="\"\"",
             allowFloats="0.0,1.0",
             ignoreFuncs="os\\.*,fmt\\.*"
          }
   ]
```

### Additional contract requirements

A `~` prefix is the required way to distinguish a regular-expression exclusion from a literal path or glob. Regex exclusions match filenames according to the expression; literal path exclusions match that path, and rule-level exclusions support glob patterns. An exclusion configured for one rule applies only to that rule and must not prevent other rules from running on the same file.
