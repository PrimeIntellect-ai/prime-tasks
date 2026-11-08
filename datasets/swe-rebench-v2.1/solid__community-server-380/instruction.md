Container metadata contains incorrect content-type
We get this when accessing a container (using a memory store):
```json
[
  {
    "@id": "http://localhost:3000/",
    "@type": [
      "http://www.w3.org/ns/ldp#Container",
      "http://www.w3.org/ns/ldp#BasicContainer",
      "http://www.w3.org/ns/ldp#Resource"
    ],
    "http://www.w3.org/ns/ldp#contains": [
      {
        "@id": "http://localhost:3000/.acl"
      }
    ],
    "http://www.w3.org/ns/ma-ont#format": [
      {
        "@value": "internal/quads"
      }
    ]
  }
]
```

The format is wrong here as these are no longer `internal/quads`. This is due to the fact that for containers the metadata is also used as data. We tried to get around this problem by delaying the data read as can be seen at
https://github.com/solid/community-server/blob/1438fd81067a9b1f2befbd8b52d2255fe22e574e/src/storage/DataAccessorBasedStore.ts#L73-L76

But in hindsight this is not going to work as the converters are going to do a read and convert that data, and at that point it can't be changed anymore.

### Additional contract requirements

- The container representation is obtained through `DataAccessorBasedStore.getRepresentation(resourceID: ResourceIdentifier): Promise<Representation>`.
- `Representation.quads()` returns the metadata quads as an array of `Quad`.
- `Representation.data` is a `Guarded<Readable>` stream of the resource's RDF data.
- `Representation.metadata.contentType` is a string; for container metadata it is `internal/quads`.
- For a container, the returned representation's data stream must match the container's metadata quads, excluding the content-type triple that the retrieval adds to the metadata.
- A container representation must have `binary: false`.
