ggcr: referrers Content-Type should indicate it is an OCI index
### Describe the bug

The referrers response should be an OCI index, but the Content-Type header says it's `text/plain`.

### To Reproduce

Run the server with referrers enabled, push content with referrers, and query with `curl -i` to see the headers.

### Expected behavior

The header should be `Content-Type: application/vnd.oci.image.index.v1+json`.

### Additional context

https://github.com/opencontainers/distribution-spec/pull/452
