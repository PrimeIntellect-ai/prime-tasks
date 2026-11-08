Using `graphcache@5.0.0` or 6 the cache in the default storage is not loaded anymore on the first page load
After upgrading from 4 to 5 (or 6) `@urql/exchange-graphcache` doing some tests with a fake delay on the backend I discovered that when I refresh the page (F5 or Ctrl+R) the cache present in the IndexedDB is not used.

**The REPL** (with SvelteKit too) is here: https://codesandbox.io/p/sandbox/romantic-feather-xmc826

**Steps**:

1. Go to https://xmc826-5173.csb.app/todos

1. the todos are downloaded, showed and stored in the IndexedDB after 3 seconds of [fake delay on the server resolver](https://codesandbox.io/p/sandbox/apollo-server-urql-svelte-crud-h1pcl?file=%2Fschema.js&selection=%5B%7B%22endColumn%22%3A25%2C%22endLineNumber%22%3A132%2C%22startColumn%22%3A7%2C%22startLineNumber%22%3A132%7D%5D)

1. Click on the reload button in the navbar (or the browser's one)

1. The "Loading listStore..." message appears during the 3 fake delay seconds

1. I expect instead to see the todos immediately (during the `cache-and-network` call which is still happening)

If I rollback only `"@urql/exchange-graphcache"` to `"4.4.3"` this "cold cache" behavior works again.

**What could be causing the problem?**

Thank you in advance.

### Urql version

[package.json](https://codesandbox.io/p/sandbox/romantic-feather-xmc826?selection=%5B%7B%22endColumn%22%3A13%2C%22endLineNumber%22%3A19%2C%22startColumn%22%3A13%2C%22startLineNumber%22%3A19%7D%5D&file=%2Fpackage.json)


### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)
