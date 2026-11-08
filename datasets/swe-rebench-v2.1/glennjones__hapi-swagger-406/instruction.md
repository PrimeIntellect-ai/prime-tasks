x-meta fields after response field merge
#### Context

* *hapi-swgger version*: 7.7.0
* *any other relevant information*:

#### What are you trying to achieve or the steps to reproduce ?

Create a route as below, with a somple Joi schema, and an extra meta data tag

```js
method:...,
path:...,
config: {
  response: {
        status: {
          201: MyJoiSchema,
        },
      },
      plugins: {
        'hapi-swagger': {
          responses: {
            201: {
              'x-meta': 'some meta data',
            },
          },
        },
      },
  },
},
handler: ...
```

#### What result did you get?

It seems if a schema is provided as normal, along with 'extra' fields in the 'hapi-swagger' plugin, the extra fields are lost in the generated swagger json. In the example above, the 'x-meta' field will be lost.

If the 'MyJoiSchema' is removed, the 'x-meta' field will not be lost.

#### What did you expect ?

I expected the 'x-meta' field to not be lost, even if a Joi schema is given
