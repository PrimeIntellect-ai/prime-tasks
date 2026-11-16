Chore: Port missing `useRole` tests from React.
When #7 was closed it didn't have *all* the tests ported quite yet, this still needs to be done.

### Additional contract requirements

- `useRole(context, options?)` returns props for three elements: `reference`, `floating`, and `item`.
- `floating` includes the floating element's `id` and, when a role is configured, its ARIA `role`. When `role` is omitted the role is `dialog`.
- `reference` includes the reference element's ARIA attributes: `aria-expanded` reflecting the open state, `aria-haspopup` set to the configured role, and `aria-controls` set to the floating element's `id` while open (and absent while closed).
- `item` is a function of an item's `active` and `selected` state that returns that item's role-specific attributes. For `role: 'select'` it returns `role: 'option'` and `aria-selected` reflecting the item's `active` and `selected` state.
- When `enabled` is `false`, `reference`, `floating`, and `item` produce no attributes.
- `useInteractions(propsList)` returns `getReferenceProps`, `getFloatingProps`, and `getItemProps`, which merge user-supplied props with the corresponding props from each entry in `propsList`.
