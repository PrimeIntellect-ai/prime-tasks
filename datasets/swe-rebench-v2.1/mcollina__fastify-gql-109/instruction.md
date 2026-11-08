Support for Content-Type: application/graphql
Add support for [application/graphql](https://graphql.org/learn/serving-over-http/#post-request) Content-Type.

express-graphql already supports it, while appolo-server does not.

It is true, that GQL variables can not be passed as part of the query, but it becomes much easier to use in command line, automated tests and [benchmarks](https://github.com/the-benchmarker/graphql-benchmarks).
