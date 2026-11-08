Invalidate doesn't work as expected for some of the queries, or components not getting rerendered with new data
### Describe the bug

Basically, I invalidate a bunch of root queries on mutation. It goes through successfully, but then queries that got invalidated are not getting reexeucted from the network. Or it does, and one of the components (freshly rendered) is updated, but the rest of the subscribed to the same query components hold on to old data.

This is how it looks in the dev tools.

Some did refetch as you can see with the green thing, but some are instant weird reexecutions that lead to nothing.
<img width="694" alt="CleanShot 2023-06-07 at 22 03 59@2x" src="https://github.com/urql-graphql/urql/assets/3940079/7be44be8-a144-4ab6-9ab3-a2617462c230">

It looks like a series (15-20 of them) of teardown, execute, update, execute, update, teardown, execute, update.

It's hard to make a reproduction, but this is what my update function looks like.

```ts
  updates: {
    Mutation: {
      organizationCreateWithExistingSafe: (_parent, _args, cache, _info) => {
        cache.invalidate("Query", "organizations" as keyof Query)
        cache.invalidate("Query", "safes" as keyof Query)
      },

```
Maybe I don't understand something?

It's important to note that these two queries are shared extensively in UI through a hook like.
```
export const useSafesQuery = () => {
  return useQueryData({ query: UseSafes_SafesDocument })
}
```
And there are at least 2 consumer components on the page rendered at the point of invalidation.
Since there is no warning against such a thing in docs, it's quite a common pattern in the codebase for very reusable stuff like user info etc. that makes no sense to re-query all the time.

Also, it's important to note that network policy everywhere is the default one, so `cache-first` and not `cache-and-network` or `network-only`.

REPRO ATTACHED HERE IS NOT A REPRO. I don't have time to build a repro, especially since it DOES invalidate others correctly rather 90% of the time so to build one is virtually impossible.

I can hop on a call anytime to show it off to anyone interested if that would be easiest.

### Reproduction

https://codesandbox.io/s/urql-issue-template-client-iui0o

### Urql version

    "@urql/core": "~4.0.10",
    "@urql/devtools": "~2.0.3",
    "@urql/exchange-graphcache": "~6.1.1",
    "@urql/exchange-refocus": "~1.0.2",
    "urql": "~4.0.3",
    "wonka": "~6.3.2",

### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)

### Additional contract requirements

When a mutation invalidates a query in the cache, an active query using the default `cache-first` policy must be able to run again and receive fresh network data. If multiple consumers are subscribed to that query, each must receive the refreshed data.
