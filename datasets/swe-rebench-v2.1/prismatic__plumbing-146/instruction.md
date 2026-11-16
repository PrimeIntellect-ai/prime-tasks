(map/flatten {:foo false}) -> '()
This function ignores the value `false`, which I don't think it should. I haven't looked at it carefully but I don't understand what the `(when m ...)` inside `flatten-helper` is for. Seems to work ok [HIDDEN] (but again there may be cornercases I haven't tried).

This impl seems to work ok:

```clj
(defn flatten
  "Transform a nested map into a seq of [keyseq leaf-val] pairs"
  [m]
  (when m
    ([HIDDEN]
     [] m)))
```

### Additional contract requirements

- Flattening must include `false` values as leaves at their key paths.
- A nested `nil` value must also be emitted as a leaf at its key path, rather than omitted.
