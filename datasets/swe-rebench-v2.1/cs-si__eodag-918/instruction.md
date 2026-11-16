staging status in server mode download
When downloading an OFFLINE product in server mode, use min values for `wait` and `time` and return a 202 status until product is available

### Additional contract requirements

- The minimum values used for the download retry parameters are `wait=-1` and `timeout=-1`; these are passed to the downloader when streaming an OFFLINE product in server mode.
- If an initially OFFLINE product becomes available and its downloader can stream it, return the streamed download rather than HTTP 202.
