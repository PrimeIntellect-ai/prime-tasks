feat: no-danger find props on all components (not just native)
Unless I am mistaken, it seems today that the rule `react/no-danger` has specific logic to only find usages on native elements. See the `isDOMComponent` check here:

https://github.com/jsx-eslint/eslint-plugin-react/blob/8c9ec8a3929403ac34a22c11cb9bd2575ba766bd/lib/rules/no-danger.js#L63

We think it could be useful to support non-native components as well, especially in cases like `styled-components` wrappers, or components that want to offer this prop to be forwarded internally to a native element.

This could be a new default behavior, or an opt-in behavior via a new rule option.

### Additional contract requirements

The rule accepts an options object with a `customComponentNames` property: an array of component-name patterns. When the name of a JSX element matches any of the patterns, the rule reports a `dangerouslySetInnerHTML` prop on that element just as it does for native DOM elements. Patterns use glob syntax: `*` matches any component name, `Foo*` matches names beginning with `Foo`, and `*Bar` matches names ending with `Bar`. The property defaults to an empty array, so without it no non-native components are checked.
