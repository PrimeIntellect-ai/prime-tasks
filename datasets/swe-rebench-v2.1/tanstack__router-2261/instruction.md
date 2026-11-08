Basepaths like "base%2Fpath" work properly in version 1.43.4 but not in 1.45.11
### Describe the bug

I'm trying to create a router on a basepath containing the value `%2F` (URL encoded representation of `/`).

With @tanstack/react-router version 1.43.4 (_edit_: and 1.45.0), the router respects it, and renders links to `/base%2Fpath/any-page` correctly. Example: https://stackblitz.com/edit/tanstack-router-kaytm9?file=src%2Fmain.tsx

With version 1.45.11, the router, after root route mount, redirects the browser to `/base/path` and links are rendered incorrectly to `/base/path/any-page`.
Example: https://stackblitz.com/edit/tanstack-router-dvwena?file=src%2Fmain.tsx

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-dvwena?file=src%2Fmain.tsx

### Steps to Reproduce the Bug or Issue

1. Create router with basepath containing `%2F`, like `/base%2Fpath` and serve the page with the router at `<domain>/base%2Fpath`.
2. With Chrome (or with probably any other browser), open `<domain>/base%2Fpath`.
3. Router mounts, root route mounts, and changes the URL in the address bar to `<domain>/base/path`. Links are rendered pointing to locations with the changed basepath, for example `<domain>/base/path/any-page`.

### Expected behavior

I expect browser location `<domain>/base%2Fpath` not to change. I expect Links to point to `<domain>/base%2Fpath/any-page`.

### Screenshots or Videos

_No response_

### Platform

- OS: macOS 14
- Browser: Chrome
- Version: 126.0.6478.183 (Official Build) (arm64)


### Additional context

As far as I can tell after debugging, the location is changed _after_ `rootRoute` `onEnter()` hook. At that point, the basepath ends up being decoded here https://github.com/TanStack/router/blame/main/packages/react-router/src/path.ts#L184. There's no workarounds that I could find, even moving from basepath to splat.

### Additional contract requirements

- When resolving `/path-segment/%F0%9F%9A%80to%2Fthe%2Fmoon`, the result must be `/path-segment/🚀to%2Fthe%2Fmoon`.
