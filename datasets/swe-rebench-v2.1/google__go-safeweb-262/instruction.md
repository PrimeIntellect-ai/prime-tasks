Simple file server (no dispatcher, no interceptors)
Applications frequently serve static files as a response (`.js`, `.css`, images, etc) and, for these, developers  implement unexported function to detect and set the `Content-Type`, based on the files' extension, omitting the `charset` parameter often. We might want to do this properly in the `safehttp.DefaultDispatcher`.

### Additional contract requirements

Expose the file-serving handler as `safehttp.FileServer(root string) Handler`.
