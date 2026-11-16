404 Cannot find any route matching
<!-- issue-up-forward-issue https://github.com/nuxt/nuxt/issues/15293 -->

<table><td><img width="760" height="0" src="https://github.com/nuxt/nuxt/issues/15293">

&nbsp;&nbsp;&nbsp;Forwarded from downstream issue:
- https://github.com/nuxt/nuxt/issues/15293 by @qucode1

</td></table><br>

### Environment

------------------------------
- Operating System: `Darwin`
- Node Version:     `v16.16.0`
- Nuxt Version:     `3.0.0-rc.12`
- Nitro Version:    `0.6.0`
- Package Manager:  `pnpm@6.11.0`
- Builder:          `vite`
- User Config:      `modules`, `ssr`
- Runtime Modules:  `@nuxtjs/tailwindcss@6.1.2`
- Build Modules:    `-`
------------------------------

### Reproduction

https://github.com/qucode1/nuxt-api-route-issue/blob/master/server/api/reset-password.post.ts

### Describe the bug

Server api routes that `return undefined` or nothing at all will run, but the server will return an error that does not help finding the issue:

```ts
export default defineEventHandler(async (event) => {
  try {
    console.log('resetPassword')
    return
  } catch (error) {
    console.log('reset password error', { error })
    return sendError(event, createError({
      ...error,
      statusMessage: error.message,
    }))
  }
})

```

to fix the issue you need to use `event.res.end()`, return null or anything else.

`404 Cannot find any route matching /api/reset-password`
![Bildschirmfoto 2022-10-28 um 18 00 14](https://user-images.githubusercontent.com/28145834/198681843-320b65c1-8ea5-4d39-8ecd-de11ba9ab1c2.png)


### Additional context

_No response_

### Logs

_No response_

### Additional contract requirements

- `createRouter(opts)` accepts an options object with an optional boolean property `preemptive`. When `preemptive` is `true`, the router operates in pre-emptive mode.
- In pre-emptive mode, when a matched route handler returns `undefined`, the response body is an empty string and the HTTP response status is `204`.
- In pre-emptive mode, when a request matches a route path but not the request method, a `405` "Method Not Allowed" error is raised immediately instead of falling through to other handlers.
- An unmatched request to `/404` returns a JSON error with `statusCode: 404` and `statusMessage: "Cannot find any route matching /404."`.


- For a matched route whose handler returns the string `Test`, the response text is `Test`.
