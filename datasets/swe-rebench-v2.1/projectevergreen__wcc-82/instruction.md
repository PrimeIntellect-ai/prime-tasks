add support for `addEventListener` as a no-op
## Type of Change

<!-- Delete what does not apply -->

- New Feature Request

## Summary
At the very least, we should be able to provide a no-op for [`addEventListener`](https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/addEventListener).

## Details
So a case like this should not error at least
```js
class MyComponent extends HTMLElement {
  constructor() {
    super();

    this.addEventListener('someCustomEvent', () => { console.log('it worked!'); });
  }

  connectedCallback() {
    this.innerHTML = '<h1>It worked!</h1>';
  }
}
```
