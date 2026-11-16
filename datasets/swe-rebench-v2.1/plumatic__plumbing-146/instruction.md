(map/flatten {:foo false}) -> '()
This function ignores the value `false`, which I don't think it should. I haven't looked at it carefully but I don't understand what the `(when m ...)` inside `flatten-helper` is for. Seems to work ok [HIDDEN] (but again there may be cornercases I haven't tried).

This impl seems to work ok:

```clj
(defn flatten
  "Transform a nested map into a seq of [keyseq leaf-val] pairs"
  [m]
  (when m
    ((fn flatten-helper [keyseq m]
       [HIDDEN])
     [] m)))
```

### Additional contract requirements

- When `map/flatten` encounters `false` or `nil` as a map leaf, it must include that value in the output as a `[keyseq leaf-val]` pair.
