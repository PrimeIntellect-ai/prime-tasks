Passing undefined to Dialog's tabIndex removed the tabIndex on the element
## 🐛 Bug report

### Current behavior

When passing `undefined` to tabIndex on the Dialog component, the tabIndex is removed from the DOM element. This can lead to the focus "leaking" out of the focus trap, causing features such as hideOnEsc not to work.

### Steps to reproduce the bug

1. Open sandbox: https://codesandbox.io/s/reakit-tabindex-undefined-v9stm
2. Open the dialog
3. Observe there is no tabIndex on the element
4. Click the "Welcome to reakit" text
5. `document.activeElement` is now the body, pressing esc doesn't close the dialog.

### Expected behavior

Because Reakit is applying a default of `tabIndex={-1}` for me, I would expect passing undefined to have no effect.

### Possible solutions

[HIDDEN]

It looks like a tabIndex from the htmlProps will override the -1 default, even if this prop is undefined, causing the prop to be removed in the DOM. [HIDDEN]

### Additional contract requirements

- When `Dialog`'s `tabIndex` is omitted or explicitly set to `undefined`, the rendered dialog element must retain the default `tabIndex` of `-1`.
- When a caller supplies a defined `tabIndex` value, the rendered dialog element must retain that value.
