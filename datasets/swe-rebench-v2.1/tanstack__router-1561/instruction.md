`navigate` functions without `to` but with `search` causes a route error inside a layout route.
### Describe the bug

After version `1.31.7` the error started occurring. Related to #1548. @SeanCassiere

### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-1udi7f?file=src%2Froutes%2F_test%2Ftabs-example.%24someId.tsx

### Steps to Reproduce the Bug or Issue

Go to "Tabs example" route, change the tab and the error is caused. If you put the URL manually, let's say `...?tab=tab2` it renders well, but as soon as you change the tab the app crash

### Expected behavior

Both tabs work well without crashing the app.

### Screenshots or Videos

_No response_

### Platform

- OS: [macOS]
- Browser: [Arc]
- Version: [1.31.7]


### Additional context

_No response_

### Additional contract requirements

- Calling `navigate` without a `to` path but with a `search` value from inside a layout route (a route whose path contains an underscore-prefixed segment such as `_layout`) must not produce a route error. The current pathname must be preserved with the layout segments removed — for example, navigating with `search` from `/u/tanner` inside the route `/u/_layout/$username` keeps the pathname `/u/tanner` — and the supplied `search` must be applied to the resulting location.
