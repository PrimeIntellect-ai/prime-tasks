Add Link header for ACL file
Implementation of https://solid.github.io/specification/protocol#auxiliary-resources-wac;
should link to the _direct_ ACL file (regardless of whether it exists).

We should probably use `rel=acl` (but let's make this configurable so we can do `rel=http://www.w3.org/ns/solid/terms#acl` later).

### Additional contract requirements

- The ACL link writer is exported as `AclLinkMetadataWriter` from `src/ldp/http/metadata/AclLinkMetadataWriter.ts` and is constructed as `new AclLinkMetadataWriter(aclManager, rel?)`, where `aclManager` is an `AclManager` and `rel` is optional and defaults to `acl`.
- Handling a response adds a `Link` header of the form `<aclUrl>; rel="{rel}"`, where `aclUrl` is the direct ACL document of the resource identifier in the metadata, whether or not that document exists.
- Passing a custom `rel` value (for example `http://www.w3.org/ns/solid/terms#acl`) uses that value in the header instead of `acl`.
