[heading-has-content] fails when Vue component is being used inside
In our project we translate website into multiple languages and we use a special Vue component instead of a text node inside heading tags. Example:

```html
<h1>
  <Trans tag="hello_world">
</h1>
```

which in English renders as:

```html
<h1>
  Hello world!
</h1>
```

The plugin complains about it:
> error  Headings must have content and the content must be accessible by a screen reader  vuejs-accessibility/heading-has-content

Is there a way to implement some exception for specifying which components are allowed to be used inside headings?

### Additional contract requirements

The exception mechanism is configured through a rule option named `accessibleChildren`. It is an array of component names (strings). Any child element whose name matches an entry in `accessibleChildren` is treated as accessible content, so a heading containing such a child is not reported.
