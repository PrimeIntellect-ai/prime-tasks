Bug: <option> elements have a duplicate selected attribute, resulting in HTML validation errors
**Description**

When using preact-render-to-string, `<option>` elements are given a duplicate `selected` attribute in the document source, resulting in HTML validation errors when run through a tool like https://validator.w3.org/.

**Steps to reproduce**

1. CodeSandbox demo: https://codesandbox.io/s/nextjs-swr-preact-forked-fmojde?file=/pages/index.js.
2. Navigate to the URL directly: https://fmojde.sse.codesandbox.io/.
3. View page source (e.g., `Ctrl+U` on Windows).
4. Search for `selected`.
5. Observe this HTML: `<option selected value="b" selected>b</option>`.
6. Visit https://validator.w3.org/nu/?doc=https%3A%2F%2Ffmojde.sse.codesandbox.io%2F to view the validation report. Observe that one of the errors is: `Duplicate attribute selected.`

**Environment**
- Nextjs version: 12.1.4
- preact-render-to-string: 5.1.20

**Additional context**

Culprit: https://github.com/preactjs/preact-render-to-string/blob/8582f23b6ad64a3e247904d711de9b60666e2f29/src/index.js#L300

Possibly related to https://github.com/preactjs/preact-render-to-string/issues/208 for similar reasons.

Happy to put in a PR myself to fix this
