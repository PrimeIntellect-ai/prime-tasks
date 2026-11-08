`:not()` pseudo class doesn't consider element type
**Describe the bug**
`:not(element)` selector doesn't consider provided element type when matching nodes.

**To Reproduce**
The following reproduction test is currently failing in happy-dom.
```js
it('Returns all elements matching "[tabindex]:not(textarea)".', () => {
  document.body.innerHTML = `
    <div tabindex="-1"></div>
    <div tabindex="0"></div>
    <div tabindex="1"></div>
    <textarea tabindex="-1"></textarea>
  `;
  const elements = document.querySelectorAll('[tabindex]:not(textarea)');

  expect(elements.length).toBe(3);   // but actual is 0
});
```

**Expected behavior**
`:not()` pseudo class selector should properly match elements that do not match provided element type selector.
