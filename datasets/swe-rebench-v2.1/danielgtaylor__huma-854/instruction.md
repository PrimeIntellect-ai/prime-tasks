Huma no long returning default application/json header (re: most recent update v2.34)
G'day Huma team/Daniel,

We've noticed some unexpected behaviours regarding the Content-Type header in the most recent update (v2.34) where Content-Type: application/json is no longer set by default, even when:

- cfg.DefaultFormat = "application/json" is explicitly set
- The client does not send an Accept header
- cfg.NoFormatFallBack is left to the default `false`

[HIDDEN]
I'm not sure if was the intended behaviour.

Reference: https://github.com/danielgtaylor/huma/compare/v2.33.0...v2.34.0#diff-34398007f1f21b0bc55b2fe31480add48b936399f37e1ae49662d9e4dbf33a98L503

### Additional contract requirements

- When `DefaultFormat` is `application/json`, the request has no `Accept` header, and `NoFormatFallBack` is `false`, the response must include `Content-Type: application/json`.
- For an unsupported `Accept` header that results in a 406 Not Acceptable response, the response `Content-Type` must be `application/problem+json`.
