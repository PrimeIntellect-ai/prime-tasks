Problem with migrating an existing project
Hello, @ktsn, how can i use modules in root and in options in same time? like this
```
const root = new Module({
  modules: {
    // typed modules
  },
})

export const store = createStore(
  root,
  {
    modules: {
        // non typed modules
      }
  }
)
```
spread operator removes modules from `rootModuleOptions`
probably problem in creating `new Store` [https://github.com/ktsn/vuex-smart-module/blob/cfbfaaa03471c7ab3cb96cc30d51c8c9021583f9/src/index.ts#L17](https://github.com/ktsn/vuex-smart-module/blob/cfbfaaa03471c7ab3cb96cc30d51c8c9021583f9/src/index.ts#L17)

can do the same as with plugins? and i can create a PR if you agree
```
[HIDDEN]
```
this would greatly simplify the project migration

### Additional contract requirements

- When creating a store with modules declared on the root `Module` and modules supplied in the `createStore` options, both sets of modules must be available in the resulting store.
