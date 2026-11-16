Support example caption
According to [usejsdoc's example documentation](http://usejsdoc.org/tags-example.html), it's valid to caption an example tag with `<caption>...</caption>`

```
/**
 * Solves equations of the form a * x = b
 * @example <caption>Example usage of method1.</caption>
 * // returns 2
 * globalNS.method1(5, 10);
 * @returns {Number} Returns the value of x for the equation.
 */
```

### Additional contract requirements

- When `doctrine.parse(source, options)` parses an `@example` tag containing a `<caption>...</caption>` element, expose the trimmed caption text in the tag's `caption` property and retain the example content after the closing element in its `description`.
