Link's `_asChild` / `createLink` do not forward all props
### Describe the bug

The `_asChild` prop of `Link` as well as the `createLink` function that uses it look like the intended way to build wrapped links, e.g. for use in design systems (see https://github.com/TanStack/router/discussions/721 for a discussion that shows that a lot of folks want to do this).

However, both of them remove the `disabled` prop which is used in some design systems to style the resulting link. I am not sure if any other props are similarly removed, but the `_asChild` component should probably have access to all props that are passed in.

### Your Example Website or App

https://stackblitz.com/edit/github-mrrmdd?file=src%2Fmain.tsx

### Steps to Reproduce the Bug or Issue

1. See the third link does not have the disabled style
2. See the console does not log the disabled prop

### Expected behavior

1. I expect the `_asChild` component to have access to all props

### Screenshots or Videos

_No response_

### Platform

- OS: Any
- Browser: Any
- Version: 1.31.3


### Additional context

_No response_
