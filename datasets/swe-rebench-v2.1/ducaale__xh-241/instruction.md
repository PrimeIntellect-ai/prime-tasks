bug (?): xh removes the content-encoding header
Hi, and thanks for xh! I've been using it to develop a server framework, and noticed that although xh does a great job of automatically processing gzip and brotli encoded response bodies, it seems to _remove_ the Content-Encoding header from verbose display. If this is in fact a bug, would you like a patch PR?

### Additional contract requirements

- When displaying gzip, deflate, brotli, and empty gzip responses, include the corresponding Content-Length lines: `Content-Length: 48`, `Content-Length: 20`, `Content-Length: 17`, and `Content-Length: 0`, respectively.
