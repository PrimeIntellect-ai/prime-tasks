Add webid to supported scopes?
https://solid.github.io/solid-oidc/#webid-scope defines a webid scope, which is used in the client identifier document example https://solid.github.io/solid-oidc/#clientids-document

At the moment CSS rejects a client id document with "InvalidClientMetadata: invalid_client_metadata" if it includes webid in the scope.
The error is from node-oidc-provider client_schema.js with description "scope must only contain supported scopes"
(CSS does not appear to propagate this description)

[HIDDEN]

Presumably this is one of errors to be caught by https://github.com/solid/community-server/issues/838

As a workaround, "webid" can be left out from the scope in the client id document, but it seems like we'd want to discourage that?

### Additional contract requirements

- The Identity Provider must advertise `webid` as a supported scope and accept it in a client identifier document without rejecting the document as unsupported metadata.
