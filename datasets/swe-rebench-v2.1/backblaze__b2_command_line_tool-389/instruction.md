src_last_modified_millis in -info is not applying to the download
When I upload a file with src_last_modified_millis and the timestamp, when the file is downloaded it is not retaining the data, and the file displays today's date.

### Additional contract requirements

- When a file has `src_last_modified_millis` metadata, downloading it to a local file must preserve that source modification time: the downloaded file's modification time must match the timestamp in the metadata, rather than the download time.
