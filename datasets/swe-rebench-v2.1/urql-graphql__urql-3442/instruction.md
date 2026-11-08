RangeError: Maximum call stack size exceeded when using persistedExchange in front of ssrExchange
### Describe the bug

We have following setup of exchanges


```
persistedExchange(),
ssrExchange,
fetchExchange,
```

Which leads to

```
file:/node_modules/wonka/dist/wonka.mjs:246
    i(start((e => {
             ^

RangeError: Maximum call stack size exceeded
    at file:///node_modules/wonka/dist/wonka.mjs:246:14
    at file:///node_modules/wonka/dist/wonka.mjs:442:9
    at Array.<anonymous> (file://node_modules/wonka/dist/wonka.mjs:179:9)
    at file://node_modules/wonka/dist/wonka.mjs:426:17
    at Array.<anonymous> (file://node_modules/wonka/dist/wonka.mjs:235:15)
    at file://node_modules/wonka/dist/wonka.mjs:426:17
    at next (file:///node_modules/wonka/dist/wonka.mjs:974:11)
    at Object.next (file://node_modules/wonka/dist/wonka.mjs:1004:9)
    at file:///node_modules/@urql/exchange-persisted/dist/urql-exchange-persisted.mjs:90:13
    at Array.<anonymous> (file:///node_modules/wonka/dist/wonka.mjs:192:14)

```

if non-persisted query is executed.

if I exchange ssr in front of persisted Query like that

```
ssrExchange,
persistedExchange(),
fetchExchange,
```

it works - but it also re-executes queries after hydration on client-side.



### Reproduction

https://github.com/Warxcell/urql-ssr-persisted-exchange-demo

### Urql version

"@urql/core@>=4.1.0", "@urql/core@^4.0.0":
  version "4.2.0"
"@urql/vue@1.1.2":
  version "1.1.2"
"@urql/exchange-persisted@^4.1.0":
  version "4.1.0"

### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)

### Additional contract requirements

A query result restored from server-side rendering must satisfy the corresponding client query without causing another request to the API. The fix must avoid exchange-order changes that make queries run again after client hydration.
