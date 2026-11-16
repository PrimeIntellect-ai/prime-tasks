Redirects in loaders do not redirect correctly after invalidating the router
### Which project does this relate to?

Router

### Describe the bug

After calling `router.invalidate()`, any `throw redirect()`'s in `loader` functions will not redirect correctly.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-tpf14b?file=app%2Froutes%2Fposts.tsx

### Steps to Reproduce the Bug or Issue

1. Go to the "Posts" route.
2. Click on the blue "Invalidate Router" button.
3. The `loader()` function will run again, however the user will not be redirected. User gets stuck on the "Posts" route.
4. Check the console for logging statements that verify this.

### Expected behavior

The user should be redirected back to the root `/` route after clicking the invalidate router button.

### Screenshots or Videos

_No response_

### Platform

- OS: macOS
- Browser: Chrome
- Version: 129


### Additional context

_No response_

### Additional contract requirements

- The router exposes a public method `Router.invalidate()` that takes no arguments. Calling it forces all active route loaders to re-execute, and any redirect thrown during those loaders is processed so the router navigates to the redirect target.
- The package exports a public hook `useRouter()` that takes no arguments and returns the current `Router` instance — the same object created by `createRouter`.
- The package exports a public function `redirect({ to })` that accepts an object with at least a `to: string` property and returns a redirect error that can be thrown inside a loader to navigate to the given pathname.
