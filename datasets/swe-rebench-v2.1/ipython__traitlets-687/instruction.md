Multiple aliases for ArgParseConfigLoader
Hi, [in v5.0 L990](https://github.com/ipython/traitlets/commit/e3e01bc2cf2fcb4c88f6d954e2fd4e4dc283f76a#diff-faeef4cfbb1bced1eba160187ed70f9a7f115e86a98cf5ffdefcc9ef52fd527dR983), alias tuples are explicitly unpacked as 2-element tuples. I didn't manage to find any discussion on this, but I didn't see an obvious reason for introducing this restriction so I was wondering if this was accidental. The documentation currently just states that `A key in both those dictionaries [flags & aliases] might be a string or tuple of strings`. I can re-structure my applications to enumerate aliases separately, but it seems a little unnecessary and increases the length of the help menu.

 ```diff
                   if not isinstance(alias, tuple):
879,882c879,880
<                     short_alias, alias = alias, None
<                 else:
<                     short_alias, alias = alias
<                 for al in (short_alias, alias):
<                     if al is None:
<                         continue
---
[HIDDEN]
```

Happy to submit PR / unit tests if I didn't miss something.

### Additional contract requirements

- `ArgParseConfigLoader` must accept alias tuple keys containing more than two strings. Each string in the tuple must work as an alternative command-line spelling for the same target trait.
