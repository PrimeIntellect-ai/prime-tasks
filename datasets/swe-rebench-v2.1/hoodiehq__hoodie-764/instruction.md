merge `options.client` of hapi plugin into bundled `new Hoodie(options)`
see https://github.com/hoodiehq/hoodie/blob/79dde6b8c4151d803aea0a1e58463d3ad6c06663/server/plugins/client/bundle.js#L85-L92

what we want is [HIDDEN]

### Additional contract requirements

The generated bundle must pass the Hapi plugin’s supplied client option values to its Hoodie instance as valid values, including values other than strings. The bundled Hoodie options must use the Hapi plugin’s supplied URL.
