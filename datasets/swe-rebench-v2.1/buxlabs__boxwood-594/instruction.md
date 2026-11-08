Local variables are overriden
```html
<foo bar="{['baz']} />
```

would not work if there was a `bar` variable passed to the parent component
