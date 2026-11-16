t.maybe setting the value to null when missing
Is there a reason why [`t.maybe` sets the value to `null` when missing](https://github.com/gcanti/tcomb/blob/master/lib/maybe.js#L34)?

This behavior turns a missing value (e.g. `undefined`) into a value (`null`) and it looks like a potentially undesirable side-effect.

For instance this causes issues with [`tcomb-react`](https://github.com/gcanti/tcomb-react): since `null` is a valid value, React will not use the value provided by `defaultProps`.

```js
@props({
  foo: t.maybe(String)
})
class MyComponent extends React.Component {

  static defaultProps = {
    foo: 'bar'
  }

  ...
}

<MyComponent /> // Invalid value null supplied to foo
```

A more natural implementation would look like

```js
[HIDDEN]
```

Do you think that's reasonable, @gcanti?

### Additional contract requirements

- When `t.maybe` receives a Nil value, it returns that value unchanged: `null` remains `null` and `undefined` remains `undefined`.
- Non-Nil values continue to follow the wrapped type’s normal creation and hydration behavior.
