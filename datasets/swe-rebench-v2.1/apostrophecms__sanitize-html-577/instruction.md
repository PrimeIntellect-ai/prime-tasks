{allowedTags:null} allows <script>
```js
'<script>alert(1)</script>' ==
sanitizeHtml(
    '<script>alert(1)</script>',
    { allowedTags: null });

'<script>alert(1)</script>' ==
sanitizeHtml(
    '<script>alert(1)</script>',
    { allowedTags: undefined });
```

The [docs](https://github.com/punkave/sanitize-html#what-if-i-want-to-allow-all-tags-or-all-attributes) say

> ### "What if I want to allow all tags or all attributes?"
>
> Simple! instead of leaving allowedTags or allowedAttributes out of the options, set either one or both to false:
>
> ```js
> allowedTags: false,
> allowedAttributes: false
> ```

[HIDDEN]

Treating `null` equivalently to false is problematic since `null` is
much more likely as an output from a function that otherwise
returns an array than `false`, so treating `null` and `undefined`
as equivalent to `false` is a corner-case with very serious security consequences.

For example,

```js
const MY_POLICY = {
  allowedTags: computeAllowedTags()
};

function computeAllowedTags() {
  if (complexCondition) {
    return INLINE_ELEMENTS;
  } else if (anotherComplexCondition) {
    return BLOCK_AND_INLINE_ELEMENTS;
  } else if (adNauseam) {
    return FORMATTING_ELEMENTS_AND_IMAGES;
  }
  // NOTE: Missing return at bottom implies return of undefined
}
```

Since the behavior for `undefined` and `null`, `0`, `NaN`, `""` and other falsey values is not documented, [HIDDEN]

### Additional contract requirements

- When `allowedTags` is a falsey value other than exactly `false`, no tags are allowed: all markup is removed and only text content is preserved.
