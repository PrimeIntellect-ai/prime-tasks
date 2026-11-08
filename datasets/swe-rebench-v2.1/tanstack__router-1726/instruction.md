Nested route group interferes with Pathtype
### Describe the bug

When i am using nested route groups the Path type (i.e. to: "/page/component/") gets reset such that it reads from the innermost group and to the end.

Say that i have a path that is "/(auth)/org/(graphql)/$orgId/revenue" the Link will autosuggest "/$orgId/revenue" as opposed to the "/org/$orgId/revenue" as i would expect

On version: "@tanstack/react-router": "^1.35.3" i encountered an issue when i attempted to manually preloading a route with the router.preloadRoute() function.

### Your Example Website or App

https://stackblitz.com/edit/github-isj4z7?file=src%2Froutes%2F__root.tsx

### Steps to Reproduce the Bug or Issue

1. Use the Link element on Line 30
2. Attempt to find /org/$orgId/revenue

### Expected behavior

I would expect that i could get the full path, so i can target it properly from anywhere in the app.

### Screenshots or Videos

<img width="449" alt="Screenshot 2024-06-08 at 17 05 35" src="https://github.com/TanStack/router/assets/138299452/f7e60e10-8b13-4553-8c10-91930732cb3b">


### Platform

- OS: [MacOs]
- Browser: [Arc]
- Version: [Version 1.46.0 (50665)]


### Additional context

I do not know if this is part of the intentional design of route groups, there was limited documentation, but it seemed like a fair interpretation of the feature that nested groups would be supported.
