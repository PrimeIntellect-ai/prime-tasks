Transpiling short syntax to long syntax does not work for components that override special tag names
```html
<import content from="content.html"/>

<content {foo} />
```

### Additional contract requirements

When an imported component is invoked under a name that is also a special tag, shorthand attributes on that invocation must pass their specified values to the component. For example, `{foo}` passes the current value of `foo`.
