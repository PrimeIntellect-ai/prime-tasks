Jackson serializer requires Include.NON_NULL option
**Is your feature request related to a problem? Please describe.**
Kompendium currently uses the installed serializer.
For Jackson it requires the `setSerializationInclusion(JsonInclude.Include.NON_NULL)` option to display ReDoc and Swagger UI correctly.
This option might not be wanted for the installed serializer used by Ktor.


**Describe the solution you'd like**
How about providing an option to pass a separate serializer instance.


**Describe alternatives you've considered**
An alternative would be to not require specific serializer options for Kompendium.

### Additional contract requirements

- The Kompendium plugin configuration accepts an `openApiJson` option. It is a function that receives a Ktor `Routing` receiver and the `OpenApiSpec` to be served, and registers the route that serves the OpenAPI document. When the user supplies it, that route is used to serialize the document, so the user can serialize the OpenAPI document with settings separate from those of the serializer installed for Ktor.
- When no `openApiJson` option is supplied, the OpenAPI document continues to be served at `/openapi.json` using the serializer installed for Ktor.
