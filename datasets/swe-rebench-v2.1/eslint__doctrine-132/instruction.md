Support nested brackets in default values
Intent is to support the following code:

```js
/**
 * @param {Array} [foo=[1]] this is a param
 */
```

Currently the default parsing ends at the first `]` regardless if other opening `[`s are encountered. JSDoc handles this syntax properly, and usejsdoc doesn't mention it but also doesn't forbid it in its discussion of default values.
