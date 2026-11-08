Issue: Generating documentation gives error:  "Zod type ZodDate is unsupported"
Whenever I try to generate OpenAPI spec using:

```
const yamlString = new OpenAPI({
  routing: routes, // the same routing and config that you use to start the server
  config,
  version: '1',
  title: 'Posterr API',
  serverUrl: 'https://localhost:8080'
}).getSpecAsYaml();
```

I get the following error:
```
Error: Zod type ZodDate is unsupported
    at depictSchema (/Users/gmcouto/code/strider-backend/node_modules/express-zod-api/src/open-api-helpers.ts:652:11)
    at /Users/gmcouto/code/strider-backend/node_modules/express-zod-api/src/open-api-helpers.ts:124:46
    at Array.map (<anonymous>)
    at depictUnion (/Users/gmcouto/code/strider-backend/node_modules/express-zod-api/src/open-api-helpers.ts:124:18)
```

### Additional contract requirements

When OpenAPI documentation generation encounters a raw `z.date()` in an endpoint input or output schema, it must fail with an actionable error. The error must identify whether the date was used in an input or output schema and direct the developer to use `z.dateIn()` for input schemas or `z.dateOut()` for output schemas.
