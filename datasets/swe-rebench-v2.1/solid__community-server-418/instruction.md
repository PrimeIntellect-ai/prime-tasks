Write to root container with SPARQL backend
It is not possible to write new metadata to the root container when using a `SparqlDataAccessor`. The culprit is here: https://github.com/solid/community-server/blob/7cae14acf7bd7230cf249a918398e7c253c290f2/src/storage/accessors/SparqlDataAccessor.ts#L114

Since the root container does not have a parent this is going to throw an error. Since the behaviour is going to be different for the root than for other container (regarding writing containment triples to the parent), [HIDDEN]

### Additional contract requirements

- Writing metadata to a root container must succeed without adding a containment triple to a parent.
