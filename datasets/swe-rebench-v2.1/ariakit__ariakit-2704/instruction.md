items/setItems don't behave correctly with useSelectStore
### Current behavior

When passing `items` and `setItems` (as produced by `useState`) to `useSelectStore`, `items` doesn't get populated.

When `SelectPopover` gets rendered with `portal`, only some items make it through.

### Steps to reproduce the bug

1. Open sandbox: https://stackblitz.com/edit/dxcty1?file=select%2Findex.tsx&theme=dark
2. Observe the number of items printed below the select component - it says "0"
3. Uncomment line with `portal` and refresh the page
4. Observe the number of items printed below the select component - it says "2" and lists "Orange" twice


### Expected behavior

In both cases, we expect 4 items to be present, all listed in order they appear in the select.

### Workaround

https://github.com/ariakit/ariakit/issues/2697#issuecomment-1674173029

### Possible solutions

_No response_

### Additional contract requirements

- `useCollectionStore` (exported from `@ariakit/react`) accepts `items` and `setItems` options (as produced by `useState`) and keeps the supplied external `items` state up-to-date as items are rendered or removed.
