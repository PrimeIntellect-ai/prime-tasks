Accept $ref at the root of the response object
I try to write the `response` property of a fastify route like so :
```js
{
body: {
        name: 'user',
        description: 'Details of the new user to register',
        $ref: '/json-schema.json#/definitions/NewUserRequest',
      },
response: {
        '200': {
          description: 'OK',
          $ref: '/json-schema.json#/definitions/UserResponse',
        },
        '401': {
          description: 'Unauthorized',
          $ref: '/json-schema.json#/definitions/GenericErrorModel',
        },
        '422': {
          description: 'Unexpected error',
          $ref: '/json-schema.json#/definitions/GenericErrorModel',
        },
      },
}
```
This is actually based on a swagger definition from the real world project here : https://github.com/gothinkster/realworld/blob/master/api/swagger.json#L35...L73

After several attempt, I found a work-around by copying the definition of `UserResponse` like so :
```js
response: {
        '200': {
          type: 'object',
          description: 'OK',
          properties: {
            user: {
              $ref: '/json-schema.json#/definitions/User',
            },
          },
          required: ['user'],
        },
       //...
      },
}
```

Edit : note that the syntax is correctly supported for the validation (in the `body` and fastify-swagger)
