Allow jsx-no-bind to ignore dom components
In my point of view the `jsx-no-bind` rule is mostly for `PureComponent`, although there is consideration on GC performance, it should not be significant

In many cases, we need to pass some arguments to an event handler, for example:

```js
<li key={name} className={className} onClick={() => this.onClickTag(name, selected)}>{text}</li>
```

This will trigger the `jsx-no-bind` rule, here we have 2 concerns:

1. If we are using a custom component in above code, we can pass `name` and `selected` to component's `props` and call `this.props.onClick(this.props.name, this.props.selected)` to prevent such function bindings, however we cannot do this with DOM components
2. DOM components are never `PureComponent`, so a large reason for `jsx-no-bind` rule will not be a benefit for DOM components

For these reasons, I expect the `jsx-no-bind` can have a `ignoreDOMComponents` config to ignore function bindings on DOM components

### Additional contract requirements

When `ignoreDOMComponents` is enabled, bindings on custom React components must still be reported by `jsx-no-bind`; the option suppresses reports only for DOM components.
