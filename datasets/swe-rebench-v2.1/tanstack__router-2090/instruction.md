key property on a route component forces unmount/mount
### Describe the bug

[HIDDEN]

Due to this, route component is recreated, rather then reconciled, if `matchId` contains path params.

### Your Example Website or App

no example app

### Steps to Reproduce the Bug or Issue

When I have these routes:
- `view.$id.tsx`
- `view.$id.index.tsx`
- `view.$id.edit.tsx`

And navigate from `/view/one/` to `/view/two`

### Expected behavior

I expect route component of `view.$id` is not unmounted and mounted again, as due to this internal state is not preserved



### Screenshots or Videos

_No response_

### Platform

- OS: [e.g. macOS, Windows, Linux]
- Browser: [e.g. Chrome, Safari, Firefox]
- Version: [e.g. 91.1]


### Additional context

_No response_

### Additional contract requirements

- When navigation changes a path parameter while remaining on the same route, its route component must not unmount and remount; its internal state must be preserved.
