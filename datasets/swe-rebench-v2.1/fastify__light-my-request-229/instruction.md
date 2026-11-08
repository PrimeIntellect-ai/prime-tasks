Allow all application/*+json media types to be parsed with response.json()
### 🚀 Feature Proposal

Currently, light-my-request explicitly requires the response's content type to start with exactly "application/json".

https://github.com/fastify/light-my-request/blob/f895e9a3045da411a30cfe82435b4c284054bb9a/lib/response.js#L142

However, there are several adjacent subtypes, which imply JSON.parse will work, theoretically all:

```
application/[tree "."] subtype +json* [";" parameter]
```

### Motivation

I set the response's content type to "application/geo+json", my `response.json()` calls started throwing errors.

### Example

- https://www.iana.org/assignments/media-types/application/vnd.geo+json
- https://www.iana.org/assignments/media-types/application/geo+json

According to IANA, this applies to roughly 100 more media types: [Source](https://www.iana.org/assignments/media-types/media-types.xhtml)
