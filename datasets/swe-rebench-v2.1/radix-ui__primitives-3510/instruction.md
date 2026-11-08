@radix-ui/one-time-password-field: prop `type` ('text' | 'password') do nothing
## Bug report

### Current Behavior

Setting `type` prop on a `<OneTimePasswordField.Root>` component do nothing.

### Expected behavior

`type` property changes the representation of the symbols inside input:
- `text` - current behavior;
- `password` - dots (•) are shown instead of characters.

### Reproducible example

https://codesandbox.io/p/sandbox/red-dream-87jv8y

### Suggested solution

`type` property should belongs to `<OneTimePasswordField.Input />` and sets the type of the generated `<input>`.

### Your environment

<!-- Very important for us to help you debug. Please fill this out! -->

| Software         | Name(s) | Version |
| ---------------- | ------- | ------- |
| Radix Package(s) |    @radix-ui/react-one-time-password-field     |  0.1.3       |
| React            | n/a     |  19       |

### Additional contract requirements

- The `type` prop is accepted on `OneTimePasswordField.Root`. It defaults to `"text"` and sets the `type` attribute of each generated `<input>` element rendered by `OneTimePasswordField.Input`.
- With `type="password"`, the generated inputs render as password inputs (characters masked as dots); with `type="text"`, characters are shown as-is.
