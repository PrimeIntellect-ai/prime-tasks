Issues with HMR in Nuxt
Hello, thank you for this great project!

I was trying to implement v0.4.0 in a Nuxt.js project using the store in module mode. Following your instructions, I was able to make it work perfectly. Anyway, I found an issue with HMR where, I believe, the accessors created for getters, mutations, and actions lose their `this` reference.

I created a small demo with a module and root store here: https://github.com/dwightjack/nuxt-vsm-demo

### Implementation

I have created a [`demo` module](https://github.com/dwightjack/nuxt-vsm-demo/blob/master/store/demo.ts), registered it on the root store and then mapped one of its actions in a [page component](https://github.com/dwightjack/nuxt-vsm-demo/blob/master/pages/index.vue#L28).

### Step to reproduce

1. run the development env: `npm i && npm run dev`
1. on the homepage of the application write something in the input text. Everything works as expected
1. edit either the store index or the module file and save
1. HMR reloads the store
1. write again in the input box: I receive the following error:

![image](https://user-images.githubusercontent.com/104721/85257905-8148fd00-b4a1-11ea-8c56-1551ce8b5d35.png)

### Notes

Looking at vuex-smart-module custom HMR function I guess that the problem is that [HIDDEN] But I don't know if I can implement a different HMR strategy since that logic is implemented in a `store.js` file inside the `.nuxt` folder.

Any hint on where could I look to find a fix for this problem?

Thanks in advance!

### Additional contract requirements

- After HMR reloads a Nuxt store in module mode, a module’s getters, mutations, and actions must continue to work with their module `this` context.
