Cleanup the 'sanitizeUrl()' function in '/src/@utils/url.ts'
Instead of having a deny list of URIs, there should be an allow list.

### Additional contract requirements

`sanitizeUrl()` permits only the `http` and `https` URI schemes. It returns an accepted URL unchanged and returns `about:blank` for a URL using any other scheme.
