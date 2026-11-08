null is being removed when used as value in dangerouslySetInnerHTML html
Printing out `null` as the contents of an HTML text node through `dangerouslySetInnerHTML` activates the async renderer https://github.com/preactjs/preact-render-to-string/pull/333, and is removed from the output.

It used to be `undefined` but switched to `null` after this PR https://github.com/preactjs/preact-render-to-string/pull/339

E.g:

1. Correctly prints as text
```js
<p dangerouslySetInnerHTML={{ __html: undefined }} />
```

2. Activates async renderer indirectly and is removed from the output.
```js
<p dangerouslySetInnerHTML={{ __html: null }} />
```
