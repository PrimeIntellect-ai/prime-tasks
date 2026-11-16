nested-structs false positives with "struct{}"
I found some instances of "struct{}" causing the nested-structs check to fail. Based on other issues it looks like the intention is to not include struct{} in this check.
```
type test struct {
  foo []chan struct{}
  bar map[string]struct{}
}
```

If this is working as intended feel free to resolve.

p.s. Revive works great! Found multiple bugs in my code.
