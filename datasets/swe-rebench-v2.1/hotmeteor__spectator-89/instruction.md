Route parameter check with integer
Hello,

I think I have found a problem with the functionality introduced in #79 .

Failing Test:
```php
    public function [HIDDEN]()
    {
        Spectator::using('Test.v1.json');

        // When testing query parameters, they are not found nor checked by RequestValidator->validateParameters().
        Route::get('/users-by-id/{user}', function (int $user) {
            return [];
        })->middleware(Middleware::class);

        $this->getJson('/users-by-id/1')
            ->assertValidRequest();
    }
```

And add this to Test.v1.json:
```json
"/users-by-id/{user}": {
      "parameters": [
        {
          "schema": {
            "type": "integer"
          },
          "name": "user",
          "in": "path",
          "required": true
        }
      ],
      "get": {
        "summary": "Get a single user",
        "tags": [],
        "responses": {
          "200": {
            "description": "OK",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "id": {
                      "type": "integer"
                    },
                    "name": {
                      "type": "string"
                    },
                    "email": {
                      "type": "string"
                    }
                  }
                }
              }
            }
          }
        },
        "operationId": "get-users-user"
      }
    },
```

I can PR the error if you want that.

Thanks for this package.

### Additional contract requirements

- The request validator must validate route parameters against their declared schemas. The `user` path parameter declared as an integer is valid for `/users-by-id/1`.
