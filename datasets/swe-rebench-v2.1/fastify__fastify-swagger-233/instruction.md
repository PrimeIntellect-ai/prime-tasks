basePath is stripped from paths
## 🐛 Bug Report

When the `basePath` is set to `/`, the leading `/` is removed from paths.

## To Reproduce

Steps to reproduce the behavior:

```js
const Fastify = require("fastify");

const app = Fastify({
  logger: {
    level: 'info'
  }
});

app.register(require("fastify-swagger"), {
  routePrefix: "/spec",
  exposeRoute: true,
  swagger: {
    basePath: '/'
  }
});

app.route({
  method: 'GET',
  url: '/foo/bar',
  handler (request, reply) {
    reply.send()
  }
})

app.listen(8080, '127.0.0.1', (err, address) => {
  if (err) {
    app.log.error(err);
    process.exit(1);
  }
});

```

This is the generated spec:
```js
{
  "swagger": "2.0",
  "info": {
    "version": "1.0.0",
    "title": "fastify-swagger"
  },
  "basePath": "/",
  "paths": {
    "foo/bar": {
      "get": {
        "responses": {
          "200": {
            "description": "Default Response"
          }
        }
      }
    }
  }
}
```
This is not valid

## Expected behavior

I expected the following spec:

```js
{
  "swagger": "2.0",
  "info": {
    "version": "1.0.0",
    "title": "fastify-swagger"
  },
  "basePath": "/",
  "paths": {
    "/foo/bar": {
      "get": {
        "responses": {
          "200": {
            "description": "Default Response"
          }
        }
      }
    }
  }
}
```

(The same happens if the `basePath` is set to `/foo`, the path will be `/bar`)

## Environment

- *node version*: 10.19.0
- *fastify version*: 2.13.0
- *os*: Windows, Linux

---

This seems to be intentional, am I misusing the library?
