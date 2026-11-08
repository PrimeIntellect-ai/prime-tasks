Watch always triggers when watching multiple refs
[Vue 3 sandbox](https://codesandbox.io/s/busy-wildflower-7w96c?file=/src/App.vue:11-191) | [Vue 2 sandbox](https://codesandbox.io/s/naughty-chebyshev-1yztl?file=/src/App.vue)

When watching multiple sources, the watcher fires even if the sources have not changed.

```js
const number = ref(1);

const div2 = computed(() => {
  return number.value > 2 ? ">2" : "<=2";
});

const div3 = computed(() => {
  return number.value > 3 ? ">3" : "<=3";
});

watch([div2, div3], () => {
  console.log("watcher!!");
});
```

This is not the same behaviour in vue 3. In vue 3 the watcher is only trigger if `div2` or `div3` values are changed
