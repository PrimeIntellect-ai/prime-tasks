More robust download function
Some datasets are hundreds of gigabytes. Currently the default downloader provides no notion of progress, let alone support for resumption.

Surely there's a library out there that we can offload all of this to...

### Additional contract requirements

- `fuel.downloaders.base.filename_from_url(url, path=None)` returns the local filename for a URL as a string. When the response carries a `Content-Disposition` header containing a `filename=` attribute, that attribute value with surrounding quotes removed is returned; otherwise the basename of the URL path is returned. The optional `path` argument (a `str` or `pathlib.Path`) is accepted for backward compatibility and does not change the returned filename.
- `fuel.downloaders.base.download(url, file_handle, chunk_size=1024)` streams the content of `url` into the binary file-like object `file_handle` in chunks of `chunk_size` bytes and returns `None`. While downloading it displays a progress bar. If the request fails, the network-related exception raised by the `requests` library propagates to the caller.
