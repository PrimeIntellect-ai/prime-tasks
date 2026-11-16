limit and skip operation is applied before conditions
Given a set of 20 instances with a schema of :

```json
{
	"properties": {
		"_id": {
			"type": "string"
		},
                "index": {
                       "type": "number"
                }
	},
	"type": "object"
}
```
with index property values that range from 1 - 20.

If I do a JSON query on the result set with a query:

```json
{
     "ands": [
         {
              "fieldPath": "index",
              "operation": 0, //Eq
              "value": {
                  "float": 15
              }
         }
     ],
     "limit": 10,
     "skip": 0,
}
```

I expect to get a list of a single result of the instance with a property of `index = 15`.

I actually get an empty list.

The limit and skip operation is applied before the conditions so if my item is not within the limit and skip operation it won't find it.
I would expect that it would search through the whole result set for the item and then apply the limit and skip operation to the result set.
