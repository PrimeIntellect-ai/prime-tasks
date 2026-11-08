Cannot Generate Zod for type containing numeric keys
## Bug description
<!-- A clear and concise description of what the bug is. -->
It appears that ts-to-zod cannot generate the zod object when the type/interface contains an object with a numeric value for its key. Sample is from an OpenAPI typescript generated with [openapi-typescript](https://www.npmjs.com/package/openapi-typescript), but could be any interface with numeric keys.

### Input

```ts
export interface paths {
  "/job/cancel": {
    /**
     * Cancel Jobs
     * @description Cancel one or more jobs, preventing their future execution
     */
    post: {
      /**
       * Cancel Jobs
       * @description Cancel one or more jobs, preventing their future execution
       */
      requestBody?: {
        content: {
          "application/json": {
            id: string;
          } | ({
              id: string;
            })[];
        };
      };
      responses: {
        /** @description A successful response returns the id(s) of all job(s) that were cancelled. */
        200: {
          content: {
            "application/json": {
              id: string;
            } | ({
                id: string;
              })[];
          };
        };
      };
    };
  };
};
```

### Expected output

```ts
// value of responses
{
  // ...
  responses: z.object({
    200: z.object(/*...*/)
  })
}
```

### Actual output

```ts
// value of responses
{
  // ,,,
   responses: z.object({})
}
```

```txt
✖ Validating generated types
 ›   Error: 'pathsSchema' is not compatible with 'paths':
 ›   Argument of type '{ "/job/cancel": { post: { requestBody?: { content: { "application/json": { id: string; } | { id: string;
 ›    }[]; }; } | undefined; responses: {}; }; }; "/job/create": { post: { requestBody?: { content: { "application/json": { ...;
 ›    } | { ...; }[]; }; } | undefined; responses: {}; }; }; "/job/status": { ...; }; "/whoami...' is not assignable to
 ›   parameter of type 'paths'.
 ›     The types of '"/job/cancel".post.responses' are incompatible between these types.
 ›       Property '200' is missing in type '{}' but required in type '{ 200: { content: { "application/json": { id: string; } |
 ›   { id: string; }[]; }; }; }'.
```

**Versions**

- Typescript: `v4.8.3`
- Zod: `v3.19.1`
