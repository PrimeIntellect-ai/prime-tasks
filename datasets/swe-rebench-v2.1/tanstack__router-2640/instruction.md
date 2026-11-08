Router.basepath is case sensitive
### Which project does this relate to?

Router

### Describe the bug

Navigating to a basepath URL that does not match the exact case of `basepath` mangles the URL.

### Your Example Website or App

https://github.com/sethlivingston/tanstack-router/blob/862fe551ff139eacca86fa25eb6dbcbc9c84ef23/app/client.tsx#L7

### Steps to Reproduce the Bug or Issue

1. Set the router basepath to a string with uppercase letters. See the example link.
2. Navigate to a path with all lowercase letters. Don't let the browser change the case of the URL right before you navigate; it does this to be "helpful".

### Expected behavior

I expect the all URL matching to be case insensitive.

### Screenshots or Videos

_No response_

### Platform

- OS: Windows
- Browser: Edge & Chrome
- Version: latest


### Additional context

I can submit a PR for this if you'd like. It looks like it's using a common trim function that is case sensitive. You probably don't want to change the common function. Perhaps create a different one, or add an optional parameter for comparison options.

### Additional contract requirements

- `removeBasepath(basepath: string, pathname: string, caseSensitive: boolean = false)` is a public function in `packages/react-router/src/path.ts`.
  - When `caseSensitive` is `false` (the default), the leading `basepath` is matched against `pathname` case-insensitively.
  - When `caseSensitive` is `true`, the leading `basepath` is matched against `pathname` with exact case.
  - It returns the original `pathname` when the `basepath` does not match the start of `pathname` or the match is not a full path segment, an empty string when `pathname` equals `basepath`, and otherwise the `pathname` with the leading `basepath` removed.
