Unable to set a parameter of type file as optional
I am not sure if no one needed this before, but I have a use case where the file type parameter is optional, but the code below returns error before validating whether the field is required.

https://github.com/go-openapi/runtime/blob/3f9800fb72fae00e99a99db505da3b330f847e8e/middleware/parameter.go#L206-L213

[HIDDEN] Please let me know if that works.

### Additional contract requirements

- Request binding must succeed when an optional file parameter is absent.
