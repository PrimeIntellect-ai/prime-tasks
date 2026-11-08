BigQuery: complex repeated schema fields are slow
When converting rows to JSON, repeated schema fields are deepcopied causing noticeable slowdowns in complex schemas.
Since conversion is performed recursively, complex schemas containing multiple levels of repeated fields (e.g. repeated list of structs each containing multiple fields of repeated structs) are copied multiple times when converting a single row - causing even further slowdown due to redundant copying.

I've created a proposal for removing the deepcopy operation. Will reference relevant PR.

### Additional contract requirements

- `SchemaField` in `google.cloud.bigquery.schema` must preserve unknown
  properties from the REST API representation: a field created from a mapping
  must serialize back to a mapping equal to the original, including keys that
  are not part of the standard field schema (`name`, `type`, `mode`, `fields`,
  `description`, `policyTags`, `defaultValueExpression`, `precision`, `scale`,
  `maxLength`, `rangeElementType`).
- `to_schema_fields(schema_list)` in `google.cloud.bigquery.schema` must
  convert a list of field-definition mappings into `SchemaField` objects whose
  `to_api_repr()` output equals the original mappings exactly, including
  unknown keys, and must not deep-copy the input representation.
- The `LoadJobConfig.schema` setter must accept field-definition mappings that
  contain unknown keys. Serializing the configuration must preserve every
  supplied key, and assigning the schema must not mutate the passed-in list.
- The `Table.schema` setter must accept field-definition mappings that contain
  unknown keys. Serializing the table resource must preserve every supplied
  key, and assigning the schema must not mutate the passed-in list.
