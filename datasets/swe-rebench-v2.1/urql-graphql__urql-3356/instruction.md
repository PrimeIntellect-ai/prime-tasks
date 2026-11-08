graphcache: Extra variables missing in updates
### Describe the bug

I've just upgraded URQL to the latest packages, and I'm no longer receiving the extra arguments ([documentation](https://formidable.com/open-source/urql/docs/graphcache/cache-updates/#variables-for-optimistic-updates)) that I pass in to a mutation in the Graphcache's `updates`. The arguments used by the query are still present, but the additional arguments are not.

Mutation:
```
const [, deleteLike] = useMutation(DeleteLikeMutation)
...
deleteLike({id, enrolmentId})
```

Relevant graphcache config:
```
updates: {
    Mutation: {
       deleteLike(
          result,
          { id },
          cache,
          { variables: { enrolmentId } }
        ) {
           // id is present
           // enrolmentId is not present (no key or value)
        }
      }
   }
```

Using the map exchange I have confirmed that the additional variable is present on the operation before it reaches the graphcache-exchange. I've also added some logging and confirmed that the variable is present when it is first processed by the graphcache-exchange.

### Reproduction

To follow

### Urql version

```
@urql/exchange-retry@^1.2.0
@urql/exchange-graphcache@^6.3.1
@urql/exchange-auth@^2.1.6
@urql/core@4.1.1
urql@4.0.5
```

### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)
