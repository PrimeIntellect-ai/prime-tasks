@containe at rule used in makeStyles  "yanks" out the shared attribute
For a given style:

```
const useAppStyles = makeStyles({
  ....otherStyles,
  header: {
    backgroundColor: "pink",
    "@container bar (width > 400px)": {
      backgroundColor: "magenta",
      color: "orange"
    },
    "@media (min-width: 600px)": {
      backgroundColor: "green"
    }
  }
});}
```

The `backgroundColor` attribute is removed from the base style and the `@media` block when defined in the `@container` block.
Is this the expected behavior, or the `backgroundColor` should not be touched outside of the `@container` block?
If `backgroundColor` is removed from the `@container` block everything is working as expected.

Test project: https://codesandbox.io/s/griffel-container-forked-h7v2qw?file=/src/App.js

### Additional contract requirements

A declaration inside an `@container` rule must not remove or conditionally scope the same property declared in the base style or in an `@media` rule. Those declarations must continue to apply in their respective contexts.
