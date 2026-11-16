Assigning a singular `Security` schema to a `Middleware` leads to an error.
### Discussed in https://github.com/RobinTail/express-zod-api/discussions/803

<div type='discussions-op-text'>

<sup>Originally posted by **McMerph** February  8, 2023</sup>
I want to specify that a particular middleware uses JWT Bearer Authentication.
So, I added:
```
security: { type: "bearer", format: "JWT" }
```
to `createMiddleware`.
Unfortunately it didn't work -(
Error is:
```
TypeError: methods[security.type] is not a function
    at {{PROJECT_DIR}}/node_modules/express-zod-api/src/open-api-helpers.ts:801:69
    at {{PROJECT_DIR}}/node_modules/express-zod-api/src/logical-container.ts:40:15
    at Array.map (<anonymous>)
    at mapLogicalContainer ({{PROJECT_DIR}}/node_modules/express-zod-api/src/logical-container.ts:37:28)
    at depictSecurity ({{PROJECT_DIR}}/node_modules/express-zod-api/src/open-api-helpers.ts:800:29)
    at onEndpoint ({{PROJECT_DIR}}/node_modules/express-zod-api/src/open-api.ts:120:25)
    at {{PROJECT_DIR}}/node_modules/express-zod-api/src/routing-walker.ts:46:9
    at Array.forEach (<anonymous>)
    at {{PROJECT_DIR}}/node_modules/express-zod-api/src/routing-walker.ts:45:15
    at Array.forEach (<anonymous>)
```
What am I doing wrong?

---
```
security: { type: "bearer" }
```
doesn't work either.

Actually
```
security: { or: [{ type: "bearer", format: "JWT" }] }
```
or
```
security: { and: [{ type: "bearer", format: "JWT" }] }
```
both work but https://editor.swagger.io/ reports structural errors in this case (screenshot provided).
Both the middleware and the endpoint have an empty input (`input: z.object({})`) if that matters.
<img width="1725" alt="image" src="https://user-images.githubusercontent.com/29835709/217489320-92c95070-6739-49a9-8c65-3f3a6308f800.png">
</div>

### Additional contract requirements

Generating the OpenAPI specification for a middleware that declares a singular `security` schema (for example `{ type: "bearer", format: "JWT" }`) must succeed and must describe that scheme in the generated document. A bearer scheme is emitted as a security scheme with `type: http`, `scheme: bearer` and `bearerFormat: JWT`, and the operation references it under `security`. Security schemes are named `<TYPE>_<n>`, where `<TYPE>` is the uppercased scheme type and `<n>` is a per-type counter starting at 1 (for example `HTTP_1`).
