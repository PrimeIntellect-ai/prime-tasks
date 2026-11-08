CORS doesn't work with `DependsOnMethod`
I was trying `express-zod-api` and found errors with CORS.

![imagen](https://user-images.githubusercontent.com/4307697/203210766-0f69be62-acd1-4740-b2b9-31e25c5d68f0.png)

For request with methods different of GET and POST, it looks like the CORS middleware doesn't exits, similar to #514

Reproduction repository https://github.com/leosuncin/express-zod-api-cors-error

### Additional contract requirements

- When CORS is enabled (`config.cors`), an `OPTIONS` request to a route declared with `DependsOnMethod` must be handled and its response must include the `Access-Control-Allow-Methods` header listing every method declared in that `DependsOnMethod` instance together with `OPTIONS`. The order of the listed methods is not significant.
