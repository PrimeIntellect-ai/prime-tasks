nonTextTags is not working for script tag
I want to allow `script` tags only with `src` attributes from specific domains, but `nonTextTags: ['script']` option doesn't remove the code contents from it.

Or, is there other way to sanitize script contents?

## To Reproduce

```js
const content = sanitizeHtml('<script src="https://apps.elfsight.com/p/platform.js"></script><script>alert(1)</script>', {
    allowedTags: ['script'],
    allowedAttributes: {
        script: ['src'],
    },
    nonTextTags: ['script'],
    allowedScriptHostnames: ['apps.elfsight.com'],
});
```

## Expected behavior

Should return:
```
<script src="https://apps.elfsight.com/p/platform.js"></script><script></script>
// or even better, without empty script tag:
<script src="https://apps.elfsight.com/p/platform.js"></script>
```

## Describe the bug

It doesn't cleanup script contents.
```
<script src="https://apps.elfsight.com/p/platform.js" defer></script><script>alert(1)</script>
```

## Details

It doesn't work in latest version `2.5.0`.

### Additional contract requirements

- When `allowedScriptHostnames` or `allowedScriptDomains` is set, a `<script>` element with no `src` must have its contents removed and be retained as `<script></script>`.
