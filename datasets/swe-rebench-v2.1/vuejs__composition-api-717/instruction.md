`shallowReactive([])` does not return a array
code like this will easily break.

```js
const foo = shallowReactive([1, 2, 3])
foo.join(' ') // => runtime error here
```

https://github.com/vuejs/composition-api/blob/2c342d5778850904e1b35e680178b8aeb80b30d7/src/reactivity/reactive.ts#L158-L161

https://github.com/vuejs/composition-api/blob/2c342d5778850904e1b35e680178b8aeb80b30d7/src/reactivity/reactive.ts#L194-L196
