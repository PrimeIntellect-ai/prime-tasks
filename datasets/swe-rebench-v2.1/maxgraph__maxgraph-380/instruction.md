Graph.setCellStyles may not propagate style changes
Seen in #325
When calling Graph.setCellStyles to change the fillColor, the fill color doesn't change in the browser.

### Additional contract requirements

- `Graph.setCellStyles(key, value, cells?)` sets the style property named `key` to `value` on every cell in `cells` (defaulting to the current selection) and propagates the change so the rendered view reflects the new value.
- `Graph.setCellStyleFlags(key, flag, value, cells?)` sets or clears the bit `flag` of the numeric style property `key` on every cell in `cells` (defaulting to the current selection) and propagates the change so the rendered view reflects the new value. `value` is `true` to set the flag, `false` to clear it, and `null` to toggle it.
- `setCellStyles(model, cells, key, value)` in `packages/core/src/util/styleUtils.ts` sets the style property named `key` to `value` on every cell in `cells` and propagates the change so the rendered view reflects the new value.
- `setCellStyleFlags(model, cells, key, flag, value)` in `packages/core/src/util/styleUtils.ts` sets or clears the bit `flag` of the numeric style property `key` on every cell in `cells` and propagates the change so the rendered view reflects the new value.
