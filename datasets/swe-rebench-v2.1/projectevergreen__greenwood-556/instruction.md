`<script>` tags require specific ordering of attributes or else become `type="module-shim"`
## Type of Change
- [ ] New Feature Request
- [ ] Documentation / Website
- [ ] Improvement / Suggestion
- [x] Bug
- [ ] Other (please clarify below)

## Summary
Noticed as part of #554 that if you didn't organize the attributes of your `<script>` tag a specific way, your script tag would come out with the wrong type in production.

For example, this works
```html
<script type="module" src="..."></script>
```

```html
<script src="..." type="module"></script>
```

will come out as `type="module-shim"` in production builds (and so of course won't load / work)
```html
<script src="..." type="module-shim"></script>
```

## Details
This is because in [**plugin-standard-thml**](https://github.com/ProjectEvergreen/greenwood/blob/release/0.10.0/packages/cli/src/plugins/resource/plugin-standard-html.js#L272), the regex expects a pattern like this:
```js
/<script type="module-shim"/
```

Which mean it will only handle `<script>` tags of the `type` attribute comes first.  [HIDDEN]
---

One thought is to scope this kind of change to only what is in the `<head>` tag, to avoid clobbering a user's content.

### Additional contract requirements

- In a production build, a `<script>` tag in the `<head>` that has `type="module"` must still have `type="module"` in the output, whether `src` or `type` comes first in the tag.
- Text in the `<body>` that contains `type="module-shim"` must appear unchanged in the production output.
