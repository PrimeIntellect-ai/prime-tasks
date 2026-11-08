Invalid GQL Query in `buildAssociatedPRsQuery` when commits/shas empty
During the upgrade to v10.0.7 which introduced GraphQL to the `success` lifecycle method, we've noticed an increase in errors in our CI pipeline and have narrowed it down to an invalid GQL Query in  `buildAssociatedPRsQuery` as a result of the `shas` variable being empty (`context.commits`).

This may be specific to our workflow with an additional plugin, however we have the ability to force semantic release to publish a new version, which results in `context.commits` being empty and therefore a GQL query gets generated as below:

```
#graphql
query getAssociatedPRs($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
      }
 }
```

Resulting in:

```
11:56:33 GraphqlResponseError: Request failed due to following response errors:
11:56:33  - Parse error on "}" (RCURLY) at [5, 7]
```

It would be nice if the changes made in be394cfb9190b9cb8961e7a9155f39eb00cbde8b would handle empty `context.commits` as per the previous implementation.
