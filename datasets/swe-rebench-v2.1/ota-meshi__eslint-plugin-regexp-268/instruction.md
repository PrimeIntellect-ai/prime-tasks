`regexp/negation`: Strange suggested fix for Unicode property escapes
See the following:

```js
var foo = /[^\P{Ll}]/u;
```

![image](https://user-images.githubusercontent.com/20878432/124464437-7b644800-dd94-11eb-9061-9e7dd5c579e1.png)

The fix is a little longer than expected.

### Additional contract requirements

- For `/[^\P{Ll}]/u`, the suggested fix should be `/\p{Ll}/u`, preserving the compact property spelling `Ll`.
