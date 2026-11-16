ResolveInfo::getFieldSelection() doesn't merge fields correctly in some specific cases
Resolving selection sets for a Relay-type connection, I've got this piece of code:
```php
  $queryStructure = $info->getFieldSelection(2);
  return array_keys($queryStructure['edges']['node'] ?? []);
```
It works correctly for most cases, but recently I've found out that there are valid queries, which result in missing fields. Namely, queries with duplicates like:
```graphql
query duplicateSelection {
  productConnection(first: 1) {
    edges {
      node { name }
      node { updatedAt }
    }
  }
}
```
In this case, I only get `updatedAt`, and the `name` is gone (overwritten).

I've found the place to fix it, so a PR is on the way. :-)
