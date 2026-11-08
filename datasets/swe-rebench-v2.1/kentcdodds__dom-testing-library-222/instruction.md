Unable to fire event on document
- `react-testing-library` version: 5.3.0
- `react` version: 1.6.6.3
- `node` version: 8.11.3
- `yarn` version: 1.12.3

### Relevant code or config:

```js
fireEvent.keyDown(document.body, {
  key: "Escape",
  keyCode: 27,
  which: 27
});
```

### What happened:

TypeError: Cannot read property 'defaultView' of null

### Suggested solution:

https://github.com/kentcdodds/dom-testing-library/blob/master/src/events.js#L324
Should handle document and window elements (possibly in more places)
