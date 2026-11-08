Route Not found when using nested groups
### Describe the bug

Describe the bug
When i am using nested route groups i am not able to visit pages that are inside the second group.

Say that i have a path that is "/(auth)/org/(graphql)/$orgId/revenue" I will not be able to visit "(auth)/org/(graphql)$orgId/revenue" but i can visit "(auth)/org/$orgId" since it is not inside two groups.

On version: "@tanstack/react-router": "^1.44.1"


### Your Example Website or App

https://stackblitz.com/edit/github-isj4z7?file=src%2Froutes%2F__root.tsx

### Steps to Reproduce the Bug or Issue

Attempt to visit /org/$orgId/revenue

### Expected behavior

I would expect to see the route.

### Screenshots or Videos

_No response_

### Platform

Platform
OS: [MacOs]
Browser: [Arc]
Version: [Version 1.46.0 (50665)]


### Additional context

I had the issue #1725 but i never implemented the pattern in my app before now. So the error has been there from version 1.0 and i am assuming this is a bug due to the fix on the related issue

### Additional contract requirements

- The route generator (`generator(config)`) must throw an error when a route configuration file for a route group is found at `(group).tsx`. The error message must be: A route configuration for a route group was found at `(group).tsx`. This is not supported. Did you mean to use a layout/pathless route instead?
- The route generator (`generator(config)`) must throw an error when such a file is found at `nested/(group).tsx`. The error message must be: A route configuration for a route group was found at `nested/(group).tsx`. This is not supported. Did you mean to use a layout/pathless route instead?
