Setting allwedClasses for "*" tag allows all classes, regardless of the filter
```js
sanitize('<span class="not-allowed">Text</span>', {
        allowedTags: [...sanitize.defaults.allowedTags, 'span'],
        allowedClasses: {
            '*': ['allowed'],
        },
    })
```
#### Expected:
```html
<span>Text</span>
```
#### Actual:
```html
<span class="not-allowed"></span>
```
This does not happen when `span` instead of `'*'` is used as the tag name for `allowedClasses`.

### Additional contract requirements

When `allowedClasses` contains a `'*'` entry, classes not listed there must be removed from any permitted element. If this filtering leaves an element with no classes, its `class` attribute must be omitted while the element and its text remain. A tag-specific `allowedClasses` entry must continue to restrict that tag to its own listed classes.
