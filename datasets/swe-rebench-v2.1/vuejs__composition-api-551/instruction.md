`Vue.set` does not work with reactive objects (regression in beta 15)
`Vue.set` is now failing on reactive objects (but only on SSR):

```js
const a = reactive({})
Vue.set(a, 'prop', 'value')
```

See https://codesandbox.io/s/wizardly-glitter-v9nd0?file=/pages/index.vue for a reproduction.

https://github.com/nuxt-community/composition-api/pull/251
