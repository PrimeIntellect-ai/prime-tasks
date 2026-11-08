graphcache: support inline fragments without type conditions
Graphcache has an uncovered edge case that is misbehaving related to inline fragments.

```graphql
query A {
  ... {
    field
  }
}

query B {
  ... @skip(if: false) {
    field
  }
}
```

The `typeCondition` for `InlineFragmentNode` is optional, yet when it's missing the fragment is skipped in both of the above conditions.
