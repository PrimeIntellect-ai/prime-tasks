`User` and `Group` resources throwing `400 Bad Request` for missing or invalid handler implementations
Currently, the read, write, and patch methods of the `SCIMMY.Resources.User` and `SCIMMY.Resources.Group` classes pass return values from declared ingress/egress/degress handlers directly to their corresponding schema classes for instantiation. When these handlers are either missing, or do not return expected values, the schema class constructor will throw a `TypeError` exception, as it expects the supplied value to be an object. This `TypeError` exception is then rethrown as a `SCIMError` exception with properties indicating an issue with the request, which is technically incorrect.

**Steps to Reproduce:**
Instantiate a resource and call one of the listed methods without first declaring the ingress/egress/degress handler implementations (either directly or at resource declaration), or after declaring a handler implementation that does not return a value where it is expected to
```js
// This, or any other read/write/patch variation that expects return values from handlers
await new SCIMMY.Resources.User("any value").read();
```

**Expected Behaviour:**
Missing handler implementations should throw `501 Not Implemented` exceptions
```js
SCIMError {
   status: 501,
   scimType: null,
   message: "Method 'egress' not implemented by resource 'User'"
}
```

Handler implementations that do not return a value when expected should throw `500 Internal Server Error` exceptions
```js
SCIMError {
   status: 500,
   scimType: null,
   message: "Unexpected empty value returned by handler"
}
```

**Actual Behaviour:**
A `400 Bad Request` exception is thrown, incorrectly indicating an issue with the request format
```js
SCIMError {
   status: 400,
   scimType: "invalidValue",
   message: "Expected 'data' parameter to be an object in SchemaDefinition instance"
}
```

### Additional contract requirements

- When a `read` or `write` handler returns a non-object value other than `undefined`, a `500` error with `scimType: null` and the exact message `Unexpected invalid value returned by handler` is thrown.
- Calling `patch` on a resource instance that has no ID throws a `404` error.


- If a `read` handler returns an empty array, it must instead throw a `500` error with `scimType: null` and the exact message `Unexpected empty value returned by handler`.
