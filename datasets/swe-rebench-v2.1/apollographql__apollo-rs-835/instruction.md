Enum values provided to scalars
Validation does not currently accept something like this:

```graphql
scalar Currency
type Query {
  convertToUSD(amount: Int!, currency: Currency!): Int!
}

query {
  convertToUSD(amount: 100, currency: EUR)
}
```

which is accepted by graphql-js and (rarely) used by customers. I don't love it, but we already accept enum values nested inside lists or objects as input for custom scalars, so it makes sense to accept this too.
