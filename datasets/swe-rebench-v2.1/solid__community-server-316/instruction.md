Support `*/*` Accept header for RDF data
The `BasicResponseWriter` errors when it receives non-binary data, so we should make sure this never happens. Currently it can still happen with an `*/*` accept header if the backend returns a stream of Quads.
Have conditional data conversion
Related to https://github.com/solid/community-server/issues/137#issuecomment-721574716 and https://github.com/solid/community-server/issues/276#issuecomment-721571262.

In both cases mentioned above we want to convert `internal/quads` to turtle, but not touch any other data (unless specifically requested).

Hopefully it is possible to have 1 clean solution that covers both cases, hence the generic issue name. One solution would be to [HIDDEN]

Perhaps something could be done with [HIDDEN], but [HIDDEN] if the preferences don't match the data but no alternative is provided.

### Additional contract requirements

- `src/storage/conversion/ConversionUtil.ts` exposes two public functions.
- `matchingTypes(preferences, types)` takes a `RepresentationPreferences` and an array of media-type strings, and returns the `RepresentationPreference` entries (each with a `value` and a `weight`) that apply to those types. It must:
  - Throw an `UnsupportedHttpError` with the message `Output type required for conversion.` when `preferences.type` is not an array.
  - Throw an `UnsupportedHttpError` with the message `Duplicate type preference found: <type>.` when the same media-type value occurs more than once in `preferences.type`.
  - Throw an `InternalServerError` with the message `Unexpected type preference: <type>.` when a supplied type string is not a valid media type.
  - Treat `internal/*` as having weight 0 unless the preferences explicitly request an internal type, so internal types are only returned when explicitly requested.
  - For each supplied type, use the most specific applicable preference weight (exact match, then `type/*`, then `*/*`), and omit entries whose resulting weight is 0.
- `checkRequest(request, inputTypes, outputTypes)` validates a conversion request and returns nothing. It must:
  - Throw an `UnsupportedHttpError` with the message `Input type required for conversion.` when the representation has no content type.
  - Throw an `UnsupportedHttpError` with the message `Can only convert from <inputTypes> to <outputTypes>.` when the representation's content type does not match any of `inputTypes`, or when the preferences do not match any of `outputTypes`.
- A representation without a content type cannot be converted: attempting to convert it fails with an `InternalServerError`.
- When an `Accept: */*` request receives data of type `internal/quads`, return the RDF data serialized as Turtle rather than exposing the internal representation. Do not convert other data that is already acceptable solely because a wildcard is present; leave it unchanged unless the requested format specifically requires conversion.
