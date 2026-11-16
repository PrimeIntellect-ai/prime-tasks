6.3.1 breaks autosave example
### Are you submitting a **bug report** or a **feature request**?
Bug report

### What is the current behavior?

Upon updating to 6.3.1, the AutoSave example no longer works. "values" is always undefined and thus AutoSave never submits form changes.

### What is the expected behavior?

That the AutoSave example would work, or be updated to work.

### Sandbox Link

https://codesandbox.io/s/react-final-form-auto-save-with-debounce-flqx3

### What's your environment?

React-Final-Form: 6.3.1
Final-Form: 4.18.6
React: 16.12.0

### Additional contract requirements

- `useFormState()` is a public hook exported from `src/index.js`. Called with no arguments inside a component that is a descendant of `<Form>`, it returns an object representing the current form state. Every key of the returned object (for example `values`, `errors`, `touched`, `dirty`) is enumerable, so `Object.keys(state)` returns a non-empty list and the state can be spread like a plain object.
- `Form` is a public component exported from `src/index.js`. It accepts an `onSubmit` function and a `children` render prop that receives the form API, including `handleSubmit`, and provides the form context to its descendants.
- `FormSpy` is a public component exported from `src/index.js`. When given a `component` prop, that component receives the subscribed form state (including `values`) as props and re-renders with the updated state whenever the subscribed values change.
