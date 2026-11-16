Error when getting the default of a type
```
title: Books API
version: 1.0
protocols: HTTP
baseUri: myApi

/books:
  get:
    description: Retrieve a list of all the users
    responses:
      200:
        body:
          application/json:
            default: {'name':'ray'}
```
`Internal error while trying to call public abstract java.lang.String org.raml.v2.api.model.v10.datamodel.TypeDeclaration.defaultValue()`

### Additional contract requirements

- When a type declaration has an object or array default, calling `defaultValue()` must succeed and return a JSON string representing the declared default, preserving its values and structure.
