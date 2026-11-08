Not reporting errors when adding attaching additional props
I would expect this to fail:

```js
const StyledLightBulbIcon = styled(Icon).attrs({ iconName: 'light_bulb' })`
  svg-bad-selector {
    height: 50px;
  }
`
```

However it doesn't.  I passes without an issue.  When I remove the call to the `.attrs` function, it fails with an error.

```js
const StyledLightBulbIcon = styled(Icon)`
  svg-bad-selector {
    height: 50px;
  }
`
```

```
src/components/task/list.jsx
 10:3  ✖  Unexpected unknown type selector "svg-bad-selector"   selector-type-no-unknown
```

Is there an option that can be passed into the CLI to ensure that it validates the styles when the `.attrs` function is being used?
