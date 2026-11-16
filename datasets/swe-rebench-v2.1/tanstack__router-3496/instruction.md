Search params get stripped if validateSearch throws and beforeLoad redirects
### Which project does this relate to?

Router

### Describe the bug

If a route has both a `validateSearch` and a `beforeLoad` that redirects:
```ts
export const Route = createFileRoute('/about')({
  validateSearch: zod.object({
    a: zod.number(),
  }),
  beforeLoad: async ({ search }) => {
    throw redirect({ to: '/third', search });
  },
});
```
When landing on such page with an *invalid search*, the `search` object forwarded through the redirection is an *empty object*.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-yhzqerey?file=src%2Froutes%2Fabout.tsx

### Steps to Reproduce the Bug or Issue

1. from the `/` homepage on the stackblitz repro above
2. click on the "to about page with search" link

### Expected behavior

I would have expected either:
- to remain on the "/about" page, in an error state (`errorComponent`)
- or to be redirected to the "/third" page, with the `search` untouched

But instead, we're redirected correctly, but the search becomes an empty object. There is no indication of an error:
- no `errorComponent` gets mounted
- no `onError` callback gets called

### Screenshots or Videos

_No response_

### Platform

- OS: macOS
- Browser: Chrome
- Version: 1.95.1


### Additional context

_No response_

### Additional contract requirements

- When `validateSearch` fails for a route and no redirect is performed, the router must not strip the search parameters from the current URL: the current location's query string must be preserved (the URL must not be rewritten to drop the invalid search params).
- When `validateSearch` fails for a route whose `beforeLoad` throws a redirect, the search parameters forwarded through the redirect must be preserved (the redirect target URL must carry the original search params), or the route must remain in an error state.
