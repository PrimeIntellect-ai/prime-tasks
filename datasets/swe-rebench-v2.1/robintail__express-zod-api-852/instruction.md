OpenAPI spec generates extra examples if the output schema extends the input schema
### Steps to reproduce:
- Add test (e.g. at `tests/unit/open-api.spec.ts`):
```
test("should pass over the multiple examples of an object", () => {
  const zodSchema = z.object({ a: z.string() });
  const spec = new OpenAPI({
    config: sampleConfig,
    routing: {
      v1: {
        addSomething: defaultEndpointsFactory.build({
          method: "post",
          input: withMeta(zodSchema).example({ a: "first" }),
          output: withMeta(zodSchema.extend({ b: z.string() }))
            .example({ a: "first", b: "prefix_first" })
            .example({ a: "second", b: "prefix_second" }),
          handler: async ({ input: { a } }) => ({ a, b: `prefix_${a}` }),
        }),
      },
    },
    version: "3.4.5",
    title: "Testing Metadata:example on IO parameter",
    serverUrl: "http://example.com",
  }).getSpecAsYaml();
  expect(spec).toMatchSnapshot();
});
```
- Add snapshot (e.g. at `tests/unit/__snapshots__/open-api.spec.ts.snap`):
```
exports[`Open API generator Metadata should pass over the multiple examples of an object 1`] = `
"openapi: 3.0.0
info:
  title: Testing Metadata:example on IO parameter
  version: 3.4.5
paths:
  /v1/addSomething:
    post:
      responses:
        "200":
          description: POST /v1/addSomething Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    enum:
                      - success
                  data:
                    type: object
                    properties:
                      a:
                        type: string
                      b:
                        type: string
                    required:
                      - a
                      - b
                    example:
                      a: first
                      b: prefix_first
                required:
                  - status
                  - data
              examples:
                example1:
                  value:
                    status: success
                    data:
                      a: first
                      b: prefix_first
                example2:
                  value:
                    status: success
                    data:
                      a: second
                      b: prefix_second
        "400":
          description: POST /v1/addSomething Error response
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    enum:
                      - error
                  error:
                    type: object
                    properties:
                      message:
                        type: string
                    required:
                      - message
                required:
                  - status
                  - error
              examples:
                example1:
                  value:
                    status: error
                    error:
                      message: Sample error message
      requestBody:
        content:
          application/json:
            schema:
              description: POST /v1/addSomething request body
              type: object
              properties:
                a:
                  type: string
              required:
                - a
            examples:
              example1:
                value:
                  a: first
components:
  schemas: {}
  responses: {}
  parameters: {}
  examples: {}
  requestBodies: {}
  headers: {}
  securitySchemes: {}
  links: {}
  callbacks: {}
tags: []
servers:
  - url: http://example.com
"
`;
```
- run test

### Actual behaviour:
The above test fails because there are extra generated examples in the endpoint `requestBody`:
```
                  - a
                  examples:
                    example1:
                      value:
                        a: first
    +               example2:
    +                 value:
    +                   a: first
    +                   b: prefix_first
    +               example3:
    +                 value:
    +                   a: second
    +                   b: prefix_second
    +               example4:
    +                 value:
    +                   a: first
    +                   b: prefix_first
    +               example5:
    +                 value:
    +                   a: first
    +                   b: prefix_first
    +               example6:
    +                 value:
    +                   a: second
    +                   b: prefix_second
    +               example7:
    +                 value:
    +                   a: first
    +                   b: prefix_second
    +               example8:
    +                 value:
    +                   a: first
    +                   b: prefix_first
    +               example9:
    +                 value:
    +                   a: second
    +                   b: prefix_second
      components:
        schemas: {}
        responses: {}
        parameters: {}
        examples: {}
```

### Expected behaviour
The above test passes.

---
The workaround is to use
```
input: withMeta(zodSchema.extend({})).example(...
```
instead of
```
input: withMeta(zodSchema).example(...
```
So my guess is that the reason for this behaviour is that [withMeta mutates its argument](https://github.com/RobinTail/express-zod-api/blob/712560ca135da7fe08b11cb7bfacb1fb3070aa1c/CHANGELOG.md#L1218)
