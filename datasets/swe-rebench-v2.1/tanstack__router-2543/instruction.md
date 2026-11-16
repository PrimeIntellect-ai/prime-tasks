Redirect in beforeload with hash adds double hash to browser URL
### Which project does this relate to?

Router

### Describe the bug

When throwing a redirect in a routes beforeload, that includes a hash. The new route will have two hashtag symbols.

ie.
```ts
throw redirect({
  to: '/about',
  hash: 'example'
});

console.log(window.location.hash)
// ?^ ##about
```.

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-wsmbuc?file=src%2Froutes%2Findex.tsx

### Steps to Reproduce the Bug or Issue

1. Load any route that doesn't include a hash
2. Refer to the page which should show the `window.location.hash`
3. There is two hashtags

### Expected behavior

When I redirect in before load, and the beforeload has a hash, there should only be one hashtag symbol in the route.

### Screenshots or Videos

_No response_

### Platform

- OS: [e.g. macOS, Windows, Linux]
- Browser: [e.g. Chrome, Safari, Firefox]
- Version: [e.g. 91.1]


### Additional context

This seems to be fine for normal navigate function or links, it's just the redirect function in before load (and possible the loader although untested)
