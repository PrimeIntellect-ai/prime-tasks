Add mandatory version param for `Rest.request`
See https://github.com/ably/specification/pull/89

### Additional contract requirements

- `AblyRest.request` must treat `version` as a required argument: calling it without a `version` argument must raise an error rather than silently falling back to a default version.
- The supplied `version` value must determine the protocol version sent with the REST request; it must not be ignored or replaced with a default.
