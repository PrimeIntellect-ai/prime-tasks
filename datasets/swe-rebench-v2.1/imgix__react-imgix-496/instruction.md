htmlAttributes ref function not called
**Before you submit:**

- [x] Please search through the existing issues (both open AND closed) to see if your issue has been discussed before. Github issue search can be used for this: https://github.com/imgix/react-imgix/issues?utf8=%E2%9C%93&q=is%3Aissue
- [x] Please ensure the problem has been isolated and reduced. This link explains more: http://css-tricks.com/6263-reduced-test-cases/

**Describe the bug**
Since the 9.0 release, `ref` functions passed via `htmlAttributes` are no longer working.

**To Reproduce**

```js
const handleRef = img => {
  // this should be called after the img is rendered in the DOM
}

return (
  <Imgix
    ...
    htmlAttributes={{ ref: handleRef }}
  />
}
```

**Expected behaviour**
As per the docs, the ref function passed in `htmlAttributes` should be called after the image is loaded in the DOM with a reference to the image html element.

**Information:**

- react-imgix version: v9.0
- I saw there was some work on ref handling for this release so I'm hoping this is straightforward to diagnose, but if not I can try to set up a repro. Thanks!
