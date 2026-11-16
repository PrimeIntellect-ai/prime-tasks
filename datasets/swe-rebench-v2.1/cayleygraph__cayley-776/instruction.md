graphql ko @opt
using the latest docker image, with query:

```
{
  nodes {
    id,
    status @opt
  }
}
```

I get:
```json
{
	"data": {
		"nodes": null
	}
}
```
while without @opt it is ok
```json
{
	"data": {
		"nodes": [
			{
				"id": "bob",
				"status": "cool_person"
			},
			{
				"id": "dani",
				"status": "cool_person"
			},
			{
				"id": "greg",
				"status": "cool_person"
			},
			{
				"id": "emily",
				"status": "smart_person"
			},
			{
				"id": "greg",
				"status": "smart_person"
			}
		]
	}
}
```

### Additional contract requirements

For a query that requests a primary node field together with another field marked `@opt`, the optional field must not remove primary nodes from the result. Nodes without a value for the optional field remain present, and nodes with matching optional values include those values.
