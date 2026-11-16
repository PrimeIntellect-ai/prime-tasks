Extension attributes are filtered when there's excludedAttributes param
Hi @sleelin,

We found another issue while trying to integrate with Entra ID. When calling `GET /Users?excludedAttributes=userName` the extension attributes are filtered out in response. If we remove the `excludedAttributes` param then the response is fine.

The problem seems to be caused by:
https://github.com/scimmyjs/scimmy/blob/9e81f47ceab7d0b518bc516ad088278cd0137774/src/lib/types/definition.js#L342
https://github.com/scimmyjs/scimmy/blob/9e81f47ceab7d0b518bc516ad088278cd0137774/src/lib/types/definition.js#L372-L373
https://github.com/scimmyjs/scimmy/blob/9e81f47ceab7d0b518bc516ad088278cd0137774/src/lib/types/definition.js#L306-L310

First of all, the `inclusions` are names of `attributes`, which would be `EnterpriseUser` for the SCIMMY.Schemas.EnterpriseUser extension or `name` for `new SCIMMY.Types.SchemaDefinition(name, ...)`.

Then, the logic seems to expect the key of data returned by handler [HIDDEN]

[HIDDEN]

### Additional contract requirements

- When a filter excludes a base-schema attribute, values in a schema extension must remain in the coerced response unless the filter also excludes them.
- Filters directed at a schema-extension namespace or at an attribute within that namespace must be applied to the corresponding extension data.
