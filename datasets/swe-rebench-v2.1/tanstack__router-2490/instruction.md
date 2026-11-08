Wrong route id for preloaded routes after rebuild route tree
### Which project does this relate to?

Router

### Describe the bug

After a route (it needs to have a lazy route) `/_protected/test` got preloaded, then we call `router.buildRouteTree()` to rebuild the route tree again, that route will have a wrong id `/_protected/_protected/test`.

### Your Example Website or App

https://stackblitz.com/edit/vitejs-vite-s8qswn?file=src%2FApp.tsx

### Steps to Reproduce the Bug or Issue

1. Open my StackBlitz example.
2. It should automatically run the project. If not, just `npm run start`
3. Open browser devtool's console.
4. Click the first button to print `router.routesById`, in the console you can confirm all routes' ids are fine.
5. Click the second button, it preloads the `/_protected/test` route.
6. Click the third button to run `router.buildRouteTree()`
7. Click the fourth button to print `router.routesById` again, in the console you can see the preloaded route `/test` now has a wrong id: `/_protected/_protected/test`

### Expected behavior

No matter how many times I rebuild the route tree, the result should be consistent.
I'm doing dynamic route injection, so I need to rebuild the route tree after there is a new route got injected.

### Screenshots or Videos

https://github.com/user-attachments/assets/d7db270f-4d76-4f0d-a1bc-5bc433e8c53b


### Platform

- OS: [Windows]
- Browser: [Chrome]
- Version: [1.58.3]


### Additional context

**How the issue happened**
1. This is currently how we generate id for a route instance in its `init()` method:
[HIDDEN]
Related code: https://github.com/TanStack/router/blob/main/packages/react-router/src/route.ts#L1032

2. During the first initialization of the router, everything is fine because it fall back to the path, and the path doesn't contain a prefix from parent.

3. [HIDDEN] Related code: https://github.com/TanStack/router/blob/main/packages/react-router/src/router.ts#L2247

4. [HIDDEN]

[HIDDEN]

### Additional contract requirements

- After a lazy route has been preloaded, repeated calls to rebuild the route tree must preserve the route's ID and keep it available in `router.routesById` under that same ID.
