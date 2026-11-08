fetchOperation throws "Cannot read properties of undefined" when client is offline
### Describe the bug

TypeError: Cannot read properties of undefined (reading 'status')

The [response](https://github.com/urql-graphql/urql/blob/8b1d16418a36b54ad5a027268869a36410e11303/packages/core/src/internal/fetchSource.ts#L121) gets lost
when the fetch throws an error causing the offline logic to fail since it cant check status etc.

Repro steps:
1) Open the repro codesandbox. https://codesandbox.io/s/beautiful-leakey-fg4px1
2) Open F12 and select Offline in network settings
3) Execute an mutation for example clicking the todo li item.

Expected:
The makeErrorResult to return an error down the pipe and not to throw a "Cannot read properties of undefined" error.

Actual:
The makeErrorResult fails to process the fetch response and instead throw "Cannot read properties of undefined" when trying to get the response.status.

Observations:
I have not created a full offline example here but just trying to replicate the "undefined" response issue.
The fix is to handle the throw more gracefully in the catch.





### Reproduction

https://codesandbox.io/s/beautiful-leakey-fg4px1

### Urql version

"@urql/exchange-graphcache": "^6.0.1",
"@urql/core": "^4.0.2",
"urql": "^4.0.0"

### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)
