`queryByTestId`, `getByTestId` use partial case-insensitive text match by default, which is unexpected
<!--
Thanks for your interest in the project. I appreciate bugs filed and PRs submitted!
Please make sure that you are familiar with and follow the Code of Conduct for
this project (found in the CODE_OF_CONDUCT.md file).

Please fill out this template with all the relevant information so we can
understand what's going on and fix the issue.

I'll probably ask you to submit the fix (after giving some direction). If you've
never done that before, that's great! Check this free short video tutorial to
learn how: http://kcd.im/pull-request
-->

* `dom-testing-library` version: 1.1.0
* `node` version: N/A
* `npm` (or `yarn`) version: N/A

Relevant code or config

```javascript
import { getByTestId } from "dom-testing-library";

document.getElementById("test").innerHTML = `
<div data-testid="supertest-123"></div>
`;

document.getElementById("output").innerHTML = `
${getByTestId(document, "tEsT")
  .outerHTML.replace(/</g, "&lt;")
  .replace(/>/g, "&gt;")}
`;
```

What you did:

1. Added an element with `data-testid="supertest-123"` to an empty DOM.
2. Queried the DOM via `getByTestId` by string `"tEsT"`.

What happened:

The element with `data-testid="supertest-123"` was found.

<!-- Please provide the full error message/screenshots/anything -->

Reproduction repository:

https://codesandbox.io/s/pwrpl1yy9x?module=%2Fsrc%2Findex.js

<!--
If possible, please create a repository that reproduces the issue with the
minimal amount of code possible.
-->

Problem description:

The current behavior is unexpected, the identifiers aren't supposed to be matched partially and case-insensitively.

Suggested solution:

Use case-sensitive full-string match in `queryByTestId`, `getByTestId`.

### Additional contract requirements

- `queryByTestId` and `getByTestId` accept a string, a RegExp, or a function as the matcher.
  - A string matcher matches a `data-testid` value only when it is exactly equal, case-sensitively (no partial and no case-insensitive matches).
  - A RegExp matcher matches when the RegExp matches the `data-testid` value.
  - A function matcher is invoked with the `data-testid` value and the element, and its boolean result is used.
