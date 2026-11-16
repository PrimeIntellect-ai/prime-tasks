String pattern in ID field not taken into account
**Steps to reproduce**

- Create a collection with a JSON schema:
```json
"schema": {
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^[0-7]$"
    },
    "title": {
      "title": "Title",
      "type": "string",
      "pattern": "^[0-7]$",
      "description": "Short title"
    }
}
```

* Post a record `{"id": "abc", "title": "1"}`

**Expected**

* the record should be rejected because `id` field does not match pattern

**Actual behaviour**

* pattern is verified on the title field, but not on `id`

See:

https://github.com/Kinto/kinto/blob/239deea6a3c486187e7a5dbd264434661c48560b/kinto/views/records.py#L63-L69
