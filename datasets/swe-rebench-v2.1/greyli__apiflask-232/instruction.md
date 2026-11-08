Support using external authentication library
Add a way to register an external authentication library for `@auth_required`.

### Additional contract requirements

Users must be able to register an external security scheme through the public `app.security_schemes` attribute and associate it with a route by passing the registered scheme's name to `@app.doc(security=...)`, for example `@app.doc(security='PartnerAuth')`. The route must remain protected through APIFlask's `@auth_required` workflow, and the OpenAPI operation must advertise the associated registered scheme.
