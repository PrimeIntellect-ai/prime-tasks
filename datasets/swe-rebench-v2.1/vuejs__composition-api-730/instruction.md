infinite loop when using proxyRefs with computed property
This short code gives "Uncaught RangeError: Maximum call stack size exceeded".

```js
let object = proxyRefs({
  a: computed(() => 1),
});
console.log(object.a);
```

https://codepen.io/SeregPie/pen/mdOaaBZ
