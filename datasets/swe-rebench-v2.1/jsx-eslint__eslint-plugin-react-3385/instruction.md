[7.31.4] `no-unknown-property` throwing on valid props
Related to #3380

I'm seeing the following errors in my project:

```
Unknown property 'onToggle' found
```
`<details>` supports `onToggle`.

```
Invalid property 'fill' found on tag 'path', but it is only allowed on: svg
```
`<path>` supports `fill`.

```
Unknown property 'as' found
```
`<link>` supports `as`.

---

Edit: It looks like there are even more valid use cases that this rule is not covering. I'd suggest reverting the changes to the `no-unknown-property` rule for v7 and releasing it under a new major version. [React Known Props](https://github.com/tcodes0/react-known-props)  can be used to get all the known props, and users can use the `ignore` option on the rule to add other props like [`css`](https://github.com/jsx-eslint/eslint-plugin-react/issues/3384#issuecomment-1236100291).

### Additional contract requirements

- Expand `no-unknown-property` to recognize valid React properties beyond the three reported examples, using the [React Known Props](https://github.com/tcodes0/react-known-props) catalog cited above as a source of truth. Preserve tag-specific validity: a property restricted to particular elements should be accepted on those elements and reported as invalid on others.
