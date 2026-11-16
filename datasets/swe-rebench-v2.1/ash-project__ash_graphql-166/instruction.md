Allow paginating nested relationships
**Is your feature request related to a problem? Please describe.**
Currently, passing `relay? true` to a list query enables Connection pagination on the query result. Sometimes though the requirement is having a _field_ paginated with a Connection. See for example  the `versions` field in the [Package](https://docs.github.com/en/graphql/reference/objects#package) type in the Github GraphQL API.

**Describe the solution you'd like**
There should be a way to require a list field to be paginated.

**Express the feature either with a change to resource syntax, or with a change to the resource interface**
Note that while `relay? true` is a property of _the query_, the paginated field should actually be a property of _the type_, because if e.g. an `Author` has a `posts` field that returns a `PostConnection`, then everything that returns an `Author` will have to consume `posts` with a `Connection`. This also means that the root query could be non paginated while the field is (which is actually a usecase I'm actively interested in).

So the syntax could be something like:

```elixir
graphql do
  type :author

  relay_connections: [:posts]

  queries do
    list :authors_paginated, :read, relay?: true
    list :authors, :read, paginate_with: nil # Will still have :posts paginated with the Connection
  end
end
```

I guess the only lists that could be paginated with `Connection` are relationships (but I might be wrong)

### Additional contract requirements

A resource's GraphQL configuration must provide the `paginate_relationship_with` option: a keyword mapping from relationship names to pagination strategies. The `:relay` strategy requires that relationship field to use Relay Connection pagination. This setting belongs to the GraphQL type, so the relationship remains a Connection when reached from a root query that is not itself Relay-paginated, including at nested levels.
