Do not always define `Vary` header
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

4.24.3

### Plugin version

8.5.0

### Node.js version

20.10.0

### Operating system

Windows

### Operating system version (i.e. 20.04, 11.3, 10)

11

### Description

The Fetch standard says:

>If [CORS protocol](https://fetch.spec.whatwg.org/#cors-protocol) requirements are more complicated than setting [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin) to * or a static [origin](https://html.spec.whatwg.org/multipage/browsers.html#concept-origin), `Vary` is to be used. [[HTML]](https://fetch.spec.whatwg.org/#biblio-html) [[HTTP]](https://fetch.spec.whatwg.org/#biblio-http) [[HTTP-CACHING]](https://fetch.spec.whatwg.org/#biblio-http-caching)
>
>In particular, consider what happens if `Vary` is not used and a server is configured to send [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin) for a certain resource only in response to a [CORS request](https://fetch.spec.whatwg.org/#cors-request). When a user agent receives a response to a non-[CORS request](https://fetch.spec.whatwg.org/#cors-request) for that resource (for example, as the result of a [navigation request](https://fetch.spec.whatwg.org/#navigation-request)), the response will lack [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin) and the user agent will cache that response. Then, if the user agent subsequently encounters a [CORS request](https://fetch.spec.whatwg.org/#cors-request) for the resource, it will use that cached response from the previous non-[CORS request](https://fetch.spec.whatwg.org/#cors-request), without [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin).
>
>But if `Vary: Origin` is used in the same scenario described above, it will cause the user agent to [fetch](https://fetch.spec.whatwg.org/#concept-fetch) a response that includes [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin), rather than using the cached response from the previous non-[CORS request](https://fetch.spec.whatwg.org/#cors-request) that lacks [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin).
>
>However, if [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin) is set to * or a static [origin](https://html.spec.whatwg.org/multipage/browsers.html#concept-origin) for a particular resource, then configure the server to always send [`Access-Control-Allow-Origin`](https://fetch.spec.whatwg.org/#http-access-control-allow-origin) in responses for the resource — for non-[CORS requests](https://fetch.spec.whatwg.org/#cors-request) as well as [CORS requests](https://fetch.spec.whatwg.org/#cors-request) — and do not use `Vary`.

fastify/cors seems to always define the `Access-Control-Allow-Origin` if `origin` is `*` or a string, and in that case setting `Vary` sounds like a bug.

Seems the regressor is https://github.com/fastify/fastify-cors/pull/45.

### Steps to Reproduce

1. Copypaste the example usage to `fastify-cors.js`

```
import Fastify from 'fastify'
import cors from '@fastify/cors'

const fastify = Fastify()
await fastify.register(cors, {
  // put your options here
})

fastify.get('/', (req, reply) => {
  reply.send({ hello: 'world' })
})

await fastify.listen({ port: 3000 })
```

2. Run `node fastify-cors.js`
3. See the `Vary` header is set as `Origin`.

### Expected Behavior

`Vary` should not be set for simple cases.
