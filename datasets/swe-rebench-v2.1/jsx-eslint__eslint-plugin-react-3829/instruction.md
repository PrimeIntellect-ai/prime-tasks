[Bug]: Unknown property 'precedence' found (react/no-unknown-property)
### Is there an existing issue for this?

- [X] I have searched the existing issues and my issue is unique
- [X] My issue appears in the command-line and not only in the text editor

### Description Overview

<!--Brief description-->

react v19 introduces a new `precedence` string prop to the [`<link>`](https://react.dev/reference/react-dom/components/link#props) and [`<style>`](https://react.dev/reference/react-dom/components/style#props) elements, but the `react/no-unknown-property` rule doesn’t yet know about it and generates linting errors when used:

```jsx
<>
    <link href="https://foo.bar" precedence="medium" rel="canonical" />
    <style href="unique-hash" precedence="anything">{` p { color: red; } `}</style>
</>
```

<!--What is happening? / What is the error?-->

example error:
```
  211:39  error  Unknown property 'precedence' found  react/no-unknown-property
```

<!--What command(s) did you run to reproduce issue?-->

these occur when running my `lint` npm run script: `"lint": "eslint .",`


### Expected Behavior

<!--Brief description-->

i expect the new `precedence` attribute to not be considered an “unknown” property


### eslint-plugin-react version

v7.36.1

### eslint version

v8.57.0

### node version

v22.7.0
