Allow scheme in url for static list service discovery
An error is thrown if we set an url like: https://localhost...
`java.lang.IllegalArgumentException: Address not parseable to URL: https://vaekn02h31.execute-api.us-east-1.amazonaws.com/stage/squarer for service squarer-service`

### Additional contract requirements

- `io.smallrye.stork.utils.StorkAddressUtils` exposes two public String constants: `HTTP_PREFIX` with the value `http://` and `HTTPS_PREFIX` with the value `https://`.
