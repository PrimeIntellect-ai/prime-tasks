Transform hook for modifying full documentation
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the feature has not already been requested


### 🚀 Feature Proposal

Add another `transform` (name TBC maybe `transformDocument`?) hook which exposes the generated documentation before it is published to allow for modification

### Motivation

I'm trying to create a plugin which brings together my library https://github.com/samchungy/zod-openapi for use with this.

However, my library allows for dynamic registration of OpenAPI components via the schemas.

eg. you declare `z.string().openapi({ref: 'jobId')}` and it will automatically insert `{jobId: { type: 'string' }}` into the components and leave a $ref behind.

It also allows users to add Zod Objects directly to the components section and we will replace them with converted objects.

This presents a little bit of an issue because it doesn't seem like I can modify the components during the `transform` hook you currently expose, nor would I be able to allow for the same behaviour of inserting ZodObjects into the components.

So, if you would accept a PR for this, could I expose the full documentation object before it's served so third parties could modify documentation accordingly?

### Example

```ts
const transformDocument = (document) => {
  // do whatever you want with the document
  document.components = {};
  return document;
}
```

### Additional contract requirements

- The hook is exposed as the `transformObject` option of the `@fastify/swagger` plugin, passed to `fastify.register(fastifySwagger, { ... })`.
- `transformObject` is a synchronous function.
- When the plugin is configured in OpenAPI mode (an `openapi` option is provided), the hook is called with an object containing the generated document as `openapiObject`.
- When the plugin is configured in Swagger mode (a `swagger` option is provided), the hook is called with an object containing the generated document as `swaggerObject`.
- The document returned by the hook is used as the generated documentation.
- Modifications made by the hook to the full document are reflected in the served documentation, including injecting or replacing the components section (the OpenAPI `components` section and the Swagger `definitions` section).
