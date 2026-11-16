Type:array throws an error when plugging in generated swagger into official https://editor.swagger.io/
#### Context
ERROR: `Schemas with 'type: array', require a sibling 'items: ' field`
* *hapi-swgger version*:9.1.1
* *any other relevant information*:

#### What are you trying to achieve or the steps to reproduce ?
Produce a schema definition for an endpoint that responds with an array.

Describe your issue here, include example `route` or JOI schemas.
```
      response: {
        schema: Joi.array().label("DemoArray")
      }
```

#### What result did you get?
```
					"200": {
						"schema": {
							"$ref": "#/definitions/DemoArray",
							"type": "array"
						},
						"description": "Successful"
					}

```


#### What did you expect ?

```
					"200": {
						"schema": {
							"$ref": "#/definitions/DemoArray"
						},
						"description": "Successful"
					}
```
