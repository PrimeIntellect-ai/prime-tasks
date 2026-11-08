TypeError is thrown during clone when permission is denied to repository on BitBucket
A TypeError is thrown during clone under the following circumstances:

* The repository is hosted on Bitbucket.
* The credentials (user:password) must be valid for an existing account on the server.
* The account must not have access permission to the repository.

The problem seems to be in the capabilities negotiation.

Here's the stack from the error:

```
Caused by: TypeError: Cannot read property 'split' of undefined
    at parseRefsAdResponse (/mnt/c/Users/ecroc/git/external/antora/node_modules/isomorphic-git/dist/for-node/isomorphic-git/index.js:5123:20)
    at processTicksAndRejections (internal/process/task_queues.js:93:5)
    at async Function.discover (/mnt/c/Users/ecroc/git/external/antora/node_modules/isomorphic-git/dist/for-node/isomorphic-git/index.js:5241:26)
    at async fetchPackfile (/mnt/c/Users/ecroc/git/external/antora/node_modules/isomorphic-git/dist/for-node/isomorphic-git/index.js:6041:22)
    at async fetch (/mnt/c/Users/ecroc/git/external/antora/node_modules/isomorphic-git/dist/for-node/isomorphic-git/index.js:5902:22)
    at async Object.clone (/mnt/c/Users/ecroc/git/external/antora/node_modules/isomorphic-git/dist/for-node/isomorphic-git/index.js:6413:42)
```

### Additional contract requirements

- Add a public function `parseRefsAdResponse(stream, { service })` in module `isomorphic-git/internal-apis`. It parses the refs advertisement part of the Git wire protocol.
- It resolves to an object `{ capabilities: Set<string>, refs: Map<string, string>, symrefs: Map<string, string> }`.
- It rejects with a `GitError` whose `code` is `E.AssertServerResponseFail` when the response format does not match expectations: the response does not begin with the expected `# service=<service>` line, the first ref line is missing the NUL separator between the ref and the capabilities, or a ref line is not exactly two space-separated fields.
- For such a format mismatch, the error's `data` field contains `{ expected: <string>, actual: <string> }` describing the mismatch.
