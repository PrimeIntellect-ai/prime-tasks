`no-useless-flag` false positive for `i` flag and Unicode property escapes
See the following example:

```js
var re1 = /\p{Ll}/iu;
```

![image](https://user-images.githubusercontent.com/20878432/124462849-5bcc2000-dd92-11eb-88f2-28220ade0ef9.png)

This report is incorrect as `\p{Ll}` matches all lower-case letters. The `i` flag is very much necessary.
