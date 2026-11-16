Support full whitespace conservation
Currently, e.g.

```
TypeA /* Hi, I'm a comment */ includes          TypeB
```

automatically becomes `TypeA includes TypeB` even with `ws: true`, as both parser and writer do not support full whitespace conservation.
