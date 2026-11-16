loader staleTime is NOT respected AFTER router invalidation
### Which project does this relate to?

Router

### Describe the bug

While doing a simple todo sample app, after I added a todo, I called router.invalidate() so that the loader would fire and get the new todo, but once invalidate is called once, it appears that all routes are forever in the `invalid: true` state and the loaders run over and over. This is very noticeable when you have `defaultPreload: "intent"` set.


### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-8gggny?file=app%2Froutes%2Fposts.tsx

### Steps to Reproduce the Bug or Issue

1. Go to posts layout
2. Hover over the post links and see in the terminal that all the loaders are fired
3. Hover over the post links again, and you should see no loaders are fired
4. Click the button labeled "Click here to Invalidate Router"
5. Now hover over the links and you will see the loaders fire again, but the route is not marked as `invalid: false` so hovering/clicking over and over will fire the loader again and again.

### Expected behavior

I would expect after doing router.invalidate() that the route loaders would fire again, but only once since I have defaultStaleTime set to Infinity.

### Screenshots or Videos

https://github.com/user-attachments/assets/4a6c82d4-3ca4-45d4-8793-2b9ea7a3035d


### Platform

- OS: Windows & Stackblitz
- Browser: Chrome
- Version: 126


### Additional context

_No response_

### Additional contract requirements

- `router.invalidate()` is an instance method on the router. It takes no arguments and returns a promise that resolves when the invalidation cycle has completed.
- `router.load()` is an instance method on the router. It takes no arguments and returns a promise that resolves when the loaders for the current matches have completed.
