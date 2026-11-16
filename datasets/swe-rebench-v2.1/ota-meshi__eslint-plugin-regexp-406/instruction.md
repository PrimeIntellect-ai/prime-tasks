Add suggestions to `regexp/no-dupe-disjunctions`
**Description**
It might be useful to have suggestions (but not fixes) for `regexp/no-dupe-disjunctions`.

What do think @ota-meshi?

### Additional contract requirements

- For input `/a|[ab]a/`, provide a suggestion whose output is `/a|[b]a/`.
- For input `/a+|[a-c]/`, provide a suggestion whose output is `/a+|[b-c]/`.
