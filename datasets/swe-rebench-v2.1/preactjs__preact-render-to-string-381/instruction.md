dangerouslySetInnerHTML={undefined} throws
The [type of `dangerouslySetInnerHTML`](https://github.com/preactjs/preact/blob/f5738915a0d67c87f54f0ccd5b946e7a4ce0d5c1/src/index.d.ts#L66-L68) is:

```js
dangerouslySetInnerHTML?: {
  __html: string;
};
```

However, when setting `dangerouslySetInnerHTML` to `undefined` I hit this code here:

https://github.com/preactjs/preact-render-to-string/blob/c8e54a19deb37d8060b01377172ec65bf285b4bf/src/index.js#L122-L135

Here `element` is `undefined` and I get `Cannot read properties of undefined (reading 'then')`.

[HIDDEN]

### Additional contract requirements

- The async renderer is exposed as `renderToStringAsync` and must not throw when an element's `dangerouslySetInnerHTML` prop is `undefined`.
