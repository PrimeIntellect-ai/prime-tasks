Using multi_joined with response object in object
@igorbenav I have more a question about get multi_joined. When i joined 2 table many to one. I can't not create response object in object. Example: I only create like that
```json
"data": [
    {
      "id": 0,
      "title": "string",
      "template_id": 0,
      "description": "string",
      "created_at": "2024-04-14T16:28:01.403Z",
      "created_by": "string",
      "template_title": "Example text for encryption",
      "template_description": "Example description for encryption template"
    }
  ]

```
This is response that i want
```json
"data": [
    {
      "id": 0,
      "title": "string",
      "template_id": 0,
      "description": "string",
      "created_at": "2024-04-14T16:28:01.403Z",
      "created_by": "string",
      "created_at": "2024-04-14T16:28:01.403Z",
      "created_by": "string",
      "template":{
              "title": "Example text for encryption",
              "description": "Example description for encryption template"
       }
    }
  ]
```
Please help me :(

### Additional contract requirements

- `FastCRUD.get_joined` and `FastCRUD.get_multi_joined` accept a boolean parameter `nest_joins` (default `False`).
- When `nest_joins=True`, the columns coming from a joined model are returned nested under a dictionary keyed by that join's prefix with the trailing underscore removed (for example, a join prefix `"tier_"` produces a nested key `"tier"`), instead of being flattened as prefixed keys. This applies to joins supplied through the single-join arguments (`join_model`, `join_prefix`, `join_on`, `join_schema_to_select`, `join_type`, `alias`, `join_filters`) as well as to joins supplied through `joins_config`.
- When `nest_joins=False` (the default), joined columns remain flattened as prefixed keys.
- `FastCRUD.get_joined` supports joining one or more related tables: a single join through its join arguments, or multiple joins through `joins_config`, a list of `JoinConfig` objects.
- `FastCRUD.get_multi_joined` supports a single join through its join arguments when `joins_config` is not supplied, and multiple joins through `joins_config`. With `nest_joins=True`, each row's joined columns are nested under dictionaries keyed by their prefixes.
