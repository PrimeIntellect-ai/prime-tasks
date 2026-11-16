Super slow 206 range requests
After some debugging of slow 206 responses from Flask's `send_file`, I narrowed the issue down to an interface mismatch between Waitress and werkzeug.

Deep down, werkzeug expects `wsgi.file_wrapper` to implement `seekable()` (and `seek()` and `tell()`) for efficient 206:

https://github.com/pallets/werkzeug/blob/347291802fcf89bc89660cc9dc62eb1303337bc2/src/werkzeug/wsgi.py#L576-L577

But Waitress provides no such methods in its `ReadOnlyFileBasedBuffer`, even when the underlying file-like (a regular `open` file on disk) has them:

https://github.com/Pylons/waitress/blob/f41e59826c81d7da5309e4b3694d5ac7a8bbd626/src/waitress/buffers.py#L141-L187

As a result, werkzeug uses a code path **without** `seek()`, where it keeps reading blocks from the beginning of the file until it reaches the range start offset… yuck:

https://github.com/pallets/werkzeug/blob/347291802fcf89bc89660cc9dc62eb1303337bc2/src/werkzeug/wsgi.py#L595-L604

**Motivation**: We often request 206 ranges from the end of huge files, such as ZIP archives where the "master ZIP record" lives at the end of the file. But because of the problem above, the app reads the entire multi-gigabyte ZIP file just to return the last 2 KB.

I'm not sure if this is an issue with werkzeug or waitress, but the performance is so bad that this is a show-stopper for us. Thanks.
