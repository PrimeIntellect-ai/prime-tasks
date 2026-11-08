Add: useRole hook
## Reference

https://floating-ui.com/docs/useRole

## Description

Adds base screen reader props to the reference and floating elements for a given role. This is useful to automatically apply ARIA props to the reference and floating elements to ensure they’re accessible to assistive technology, including item elements if narrowly specified.

## Props

- [x] `enabled`
- [x] `role`
- [x] `Component roles`
- [x] `Native roles`

### Additional contract requirements

- Add a public function `useRole(context, options?)` in `src/lib/hooks/useRole/index.svelte.ts`.
- `options` is a `UseRoleOptions` object with an optional `role` property of type `AriaRole | ComponentRole`, defaulting to `'dialog'`.
- Native (ARIA) roles: `'tooltip' | 'dialog' | 'alertdialog' | 'menu' | 'listbox' | 'grid' | 'tree'`.
- Component roles: `'select' | 'label' | 'combobox'`.
- The optional `enabled` option defaults to `true`; when `false`, the hook does not contribute role props to the reference or floating element.
- The floating element receives the resolved role. The component roles `select` and `combobox` resolve to the `listbox` role; `label` resolves to no role.
- The reference element receives base screen reader props for the role:
  - For `dialog` (the default), the reference element exposes `aria-haspopup="dialog"`, an `aria-expanded` value reflecting the open state, and `aria-controls` referencing the floating element while open.
  - For `tooltip`, the reference element exposes `aria-describedby` referencing the floating element while open.
  - For `label`, the reference element exposes `aria-labelledby` referencing the floating element while open.
- When the role is `select`, item elements receive the `option` role.
