Colon escaping is not reverted
### Is there an existing issue for this?

- [X] I have searched the existing issues

### Current behavior

Using colon in endpoint path like `users:find` needs to be escaped:
* `users[:]find` for express
* `users::find` for fastify

But SwaggerModule.createDocument does not revert this escape sequences and emits literal strings like `users[:]find`.

![image](https://user-images.githubusercontent.com/17786588/137479093-14b024f1-d1ba-42cd-a733-306a7f868c26.png)


Currently we are forced to use this workaround (express only):

```ts
function fixColonInEndpointPath(document: OpenAPIObject): OpenAPIObject {
  const paths = Object.fromEntries(
    Object.entries(document.paths).map(([path, endpoints]) => [
      path.replace(/\[:\]/, ':'),
      endpoints,
    ]),
  );
  return { ...document, paths };
}
```

```ts
const document = fixColonInEndpointPath(
    SwaggerModule.createDocument(
      app,
      new DocumentBuilder() ...
```

### Minimum reproduction code

https://github.com/glebbash/nestjs-swagger-colon-bug

### Steps to reproduce

1. npm install
2. npm test

### Expected behavior

SwaggerModule should detect platform (express/fastify) and revert colon escape sequences.

### Package version

5.1.0

### NestJS version

8.1.1

### Node.js version

14

### In which operating systems have you tested?

- [ ] macOS
- [ ] Windows
- [X] Linux

### Other

_No response_
