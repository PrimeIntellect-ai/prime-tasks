Fix ref resolution during response validation
Ref resolution during response validation sometimes fails because of where the validation starts. For refs to resolve 100% of the time, the scope maintained by jsonschema's RefResolver has to be rooted at `/` in swagger.json, not at the response_spec fragment that is currently passed to the `validate_response(..)` function.

[HIDDEN]

This is quite difficult to explain, so an example is probably useful to compare working and broken scopes for the RefResolver for an internal use case:

Broken RefResolver scope:
```
['file:///nail/home/spatel/pg/services/biz_app/api_docs/swagger.json']
```

Working RefResolver scope:
```
[
'file:///nail/home/spatel/pg/services/biz_app/api_docs/swagger.json',
'file:///nail/home/spatel/pg/services/biz_app/api_docs/tags/account.json#/paths/account.photo.v1',
'file:///nail/home/spatel/pg/services/biz_app/api_docs/tags/account.json#/definitions/AccountPhotoResponse'
]
```

### Additional contract requirements

During response validation, references must resolve using the full scope rooted at the Swagger document, not only the scope of the response-spec fragment. When a schema being validated carries an `x-scope` annotation recording that full scope, reference resolution must use it. When no such annotation is available, references must continue to resolve using the resolver's current scope.
