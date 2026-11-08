Add a setting to allow private fields to be indexed.
**Description**
Currently, there is no way to index `private` fields to be used for `search`, `filter`, `sort` or `display`.

**Basic example**
If I had a field that contains metadata or other value that I do not wish to include in the API responses I would make it a `private` field. However, I still may want to use this value for `search`, `filter` or `sort`. Currently, this is not possible without making the field non-private in which case it requires additional logic on the Strapi side to sanitize the field from the responses.

**Potential solutions**

1. Ignore sanitizing private fields if they appear on either `searchableAttributes`, `distinctAttribute`, `filterableAttributes`, `searchableAttributes` or `sortableAttributes`.

_Pros:_

- Does not deviate from the [Meilisearch settings spec](https://www.meilisearch.com/docs/reference/api/settings).
- Does not introduce an additional setting.

_Cons:_

- By default will be included when using `["*"]` which may not be ideal.
- Prone to be exposed by mistake.

<br/>

2. Add a new setting called `indexedPrivateAttributes` that takes an array of `private` attribute names.

_Pros:_

- Easier to distinguish and less likely to expose sensitive fields by mistake.
- Can work alongside `["*"]` as this is a separate setting.
- Can be more flexible depending on the implementation.

_Cons:_

- By default will allow full scope (`search`, `filter`, `sort`, `display`) unless an additional attribute is added to the same setting to get the `scope`.
- Will deviate from the [Meilisearch settings spec](https://www.meilisearch.com/docs/reference/api/settings).

<br/>

**Other**
PR that introduced the current behaviour: https://github.com/meilisearch/strapi-plugin-meilisearch/pull/703
Mentioned in https://github.com/meilisearch/strapi-plugin-meilisearch/issues/695

### Additional contract requirements

- The plugin configuration accepts a per-collection option named `noSanitizePrivateFields`.
- `noSanitizePrivateFields` must be either `undefined` or an array. Any other type is invalid and must produce a validation error.
- When `noSanitizePrivateFields` is present and valid, the validated configuration returned for that collection exposes the same array value.
- When `noSanitizePrivateFields` is invalid, an error is logged and no warning is emitted for this option.
- When `noSanitizePrivateFields` is invalid for the `restaurant` collection, the logged error message is exactly `The "noSanitizePrivateFields" option of "restaurant" should be an array of strings.`
- Private fields whose names are listed in `noSanitizePrivateFields` for a collection are not removed from the entries indexed in Meilisearch, while private fields that are not listed are still removed.
