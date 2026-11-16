Computed props which depend on computed props that consume store state don't update as expected
See this CodeSandbox:

[![Edit Dependent Computed Prop Issue Repro](https://codesandbox.io/static/img/play-codesandbox.svg)](https://codesandbox.io/s/dependent-computed-prop-issue-repro-rcvsgj?fontsize=14&hidenavigation=1&theme=dark)

The `readonly` computed property depends on `readonlyReason`. `readonlyReason` consumes state external to `bar` from the `foo` state slice.

When "Submit" is clicked, `readonly` should become `true` based on how the computed property is written. However it remains false. The current workaround is to define an explicit state resolver to isolate `readonlyReason`. When `readonlyReason` is accessed directly by the state resolver, `readonly` returns the expected value. See `store.ts` and try toggling the computed props to see this in action.

[HIDDEN] In this case, the inputs are equal (with no explicit state resolvers, the default state resolvers of `[(state) => state]` are used, and no local state has changed), but store state and previous store state are different, and since the prop in question depends on a computed property that depends only on external state, its not updating correctly.

I have a possible fix in mind and will test with the help of @jmyrland before opening a PR. If for some reason this cannot be fixed, we should update the documentation to cite this as a known issue.

### Additional contract requirements

- A computed property that depends on another computed property reading external store state must update when relevant store state changes, and downstream computed values must reflect the value implied by their definitions.
