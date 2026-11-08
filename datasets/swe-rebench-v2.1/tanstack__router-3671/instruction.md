useNavigate does not work when `from` is passed on hook declaration
### Which project does this relate to?

Router

### Describe the bug

Hi there! Love the tool, but the `useNavigate` hook doesn't seem to respect the `from` field. If I create the hook with `useNavigate({ from: Route.fullRoute })`, it seems to be relative to the current URL. If instead, I pass `from` directly while calling it (i.e., `const navigate = useNavigate(); navigate({ from: Route.fullRoute, ... })`), it works correctly and navigates to the URL relative to the full path of the provided route.

I'm using the `useNavigate` hook within a `route.tsx`, I'm not sure it would possible to replicate this behavior outside of a route file (since, then, the `fullRoute` would just be the current URL).

### Your Example Website or App

https://github.com/Andrew-Talley/tsr-navigate-bug

### Steps to Reproduce the Bug or Issue

This was using create tanstack-router — to set it up, just run `yarn` and `yarn start`.

From there, click on "Navigate to subfolder" and then "Go to File 2." From there, if you click on "Go Home - Inherited from" (which uses `useNavigate({ from: Route.fullPath })`), the URL doesn't change and it stays on /folder-1/folder-2/file. If you click "Go Home - Explicit from" (which uses `navigate({ from: Route.fullPath, to: '.' })`), then it does work.

### Expected behavior

Passing `from` when declaring the `useNavigate` hook should behave the same as passing it when calling the function.

### Screenshots or Videos

_No response_

### Platform

- OS: Mac
- Browser: Chrome
- Version: 1.112.13


### Additional context

_No response_
