Alias `vm.$root` with `this.root` to match with Vue 3
https://github.com/vuejs/vue-apollo/pull/1040#issuecomment-685866246 by @frandiox

### Additional contract requirements

A component's Vue 3-style `root` reference identifies the root component of its component tree, matching the component exposed by Vue 2's `vm.$root`. The root Vue instance is available as `root.proxy`.
