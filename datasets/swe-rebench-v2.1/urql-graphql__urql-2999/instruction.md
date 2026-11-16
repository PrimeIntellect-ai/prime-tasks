(graphcache): Getting non-stale flags for partial results
### Describe the bug

I'm using `urql`, `@urql/core`, `@urql/exchange-graphcache` and `@urql/exchange-execute` and I think I'm getting at least a stale state wrong. There is a small reproduction of the issue available that shows the setup, but in short:

When loading two queries (covering in part the same sections) in parallel and a partial result can be available for the slower of them the both the loading and the stale state of the slower query is set to false. This is the output I get from the reproduction (altered for clarity):

```
T1 {fetching: true, stale: false, data: undefined }
T2 {fetching: true, stale: false, data: undefined }

// T2 query is done loading (subFeature2 resolver returning)

T1 {fetching: false, stale: false, data: PARTIAL DATA }
T2 {fetching: false, stale: false, data: FULL DATA }

// T2 query is done loading (subFeature1 resolver returning)

T1 {fetching: false, stale: false, data: FULL DATA }
T2 {fetching: false, stale: false, data: FULL DATA }
```

This seems to be in contrast with the information available at <https://formidable.com/open-source/urql/docs/graphcache/schema-awareness/#partial-results> which suggest the stale flag should be set until the full data is available.

There has also been some discussions on this topic earlier in <https://github.com/urql-graphql/urql/issues/2282> which also seems to align with the documentation.

I would perhaps also expect the fetching flag to be set until the first real non-partial data is present but I don't know if that is expected or not.

### Reproduction

https://codesandbox.io/s/js-playground-forked-i715qc?file=/src/index.tsx

### Urql version

@urql/core v3.1.1
@urql/exchange-execute v2.1.1
@urql/exchange-graphcache v5.0.8
urql v3.0.3
graphql v16.6.0


### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)
