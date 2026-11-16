[Diff] Cannot compare remote schema
Repo:
https://github.com/spacexland/api/tree/graphql-inspector

Run:
```bash
graphql-inspector diff https://api.spacex.land/graphql schema.graphql
```
Output:
```bash
✖ Cannot read property '__schema' of undefined
```
Definitions in introspected schema are being pretty printed
Hi!

I'm comparing two schemas: one loaded from disk, one introspected from our endpoint. Even if they're both using identical schemas, I'm seeing differences due to newlines being added in type definition comments.

It turns out that the issue is with this process: [HIDDEN], which means that they can't be compared to the original.

I'm not sure what the best route to fix it would be, except [HIDDEN]

Cheers,
Mike

### Additional contract requirements

- Comparing otherwise identical schemas must not report differences solely because loading an introspected schema adds line breaks to type-definition comments.
