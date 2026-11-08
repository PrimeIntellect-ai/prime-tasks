Concurrent calls to `getSession` leads to only the first one getting the session
### Environment

stackblitz
h3: 1.10.0
node: 18.18

### Reproduction

Barebone reproduction using `H3Event` and `useSession` only.
[![Open in StackBlitz](https://developer.stackblitz.com/img/open_in_stackblitz.svg)](https://stackblitz.com/edit/stackblitz-starters-jyfqat?file=index.js)

Solid-Start repro by the issue author here https://github.com/solidjs/solid-start/issues/1192
[![Open in StackBlitz](https://developer.stackblitz.com/img/open_in_stackblitz.svg)](https://stackblitz.com/edit/metruzanca-solidstart-getsession-bug-repro-xd4fmg?file=README.md)

Steps (for Solid-Start Repro):

1. Press Login button
2. Refresh page - You are logged out
3. Press Index link - You are logged in

### Describe the bug

When calling `getSession` multiple times concurrently on a single page request the first call will initialize the [HIDDEN]

### Additional context

[HIDDEN]
https://github.com/unjs/h3/blob/ae91fc8658315dca75da22b665eda4175eef7ea8/src/utils/session.ts#L108

### Logs

_No response_

### Additional contract requirements

- Concurrent calls to `useSession` on the same `H3Event` must each resolve to the complete session associated with the request, including data from an existing session cookie, rather than returning an empty placeholder.
