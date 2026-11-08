cache issues when using `@defer` directive and `@urql/exchange-graphcache`
### Describe the bug

I’ve run into a pretty weird issue while using urql and I could really use some help.

The main problem is that when my app sends a query with defer or when it receives chunked data, it seems to be the last request that’s ever fired.

For example, when I open my app and navigate through random pages, everything works just fine. But when I go to a page that uses defer and then move to another random page, I get a bunch of runtime errors due to missing data. It looks like the query was resolved (cache hit), but an API request was never fired. When I refresh the page, everything works again.

After some debugging, I narrowed it down to have something to do with `@urql/exchange-graphcache` (if I remove the exchange it works fine). Based on the logs and urql devtools, there’s a cache hit for those queries when I there shouldn’t be. Also, when I remove defer usage, logs from the same flow show cache misses.

Do you have any suggestions what could be causing this?

Urql dev tools:
* There's no API call for the last four queries
* The fifth one (from the bottom) is the one with `defer` directive
<img width="859" alt="CleanShot 2023-04-18 at 17 01 19@2x" src="https://user-images.githubusercontent.com/9019397/232907214-8ef31d6e-5d4b-4f17-9f1a-fbb57ea868d0.png">

<img width="474" alt="CleanShot 2023-04-18 at 17 02 33@2x" src="https://user-images.githubusercontent.com/9019397/232907145-6642de26-261e-4a5f-9bff-b6d51d74972b.png">



Here's a PR to GraphQL Hive with adding defer to one of the queries (and necessary setup): https://github.com/kamilkisiela/graphql-hive/pull/1964

### Reproduction

https://github.com/kamilkisiela/graphql-hive/pull/1964

### Urql version

@urql/core: 4.0.4

@urql/exchange-graphcache: 6.0.1

### Validations

- [X] I can confirm that this is a bug report, and not a feature request, RFC, question, or discussion, for which [GitHub Discussions](https://github.com/urql-graphql/urql/discussions) should be used
- [X] Read the [docs](https://formidable.com/open-source/urql/docs/).
- [X] Follow our [Code of Conduct](https://github.com/urql-graphql/urql/blob/main/CODE_OF_CONDUCT.md)

### Additional contract requirements

After a query using `@defer` or a chunked result is processed, a later query requesting data that is not in the cache must be treated as a cache miss and forwarded, rather than answered as a cache hit.
