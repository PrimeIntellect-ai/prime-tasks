Refactor Google Cloud Storage to use blob.open
#### Problem description

`google-storage` has [recently added an open function to blobs ](https://github.com/googleapis/python-storage/pull/385/files)that allows for file like IO. This would greatly reduce the amount of code we have to maintain and maybe solve https://github.com/RaRe-Technologies/smart_open/issues/555.

Before you create the issue, please make sure you have:

- [ ] Described the problem clearly
- [ ] Provided a minimal reproducible example, including any required data
- [ ] Provided the version numbers of the relevant software

### Additional contract requirements

- The public function `smart_open.gcs.Writer(bucket, blob, min_part_size=None, client=None, blob_properties=None, blob_open_kwargs=None)` returns a binary file-like object for writing to the named blob, obtained by opening the blob with its `open('wb', ...)` method.
- When `blob_properties` is supplied, each key/value pair is applied as an attribute of the blob before it is opened.
- When `blob_open_kwargs` is supplied, those keyword arguments are forwarded to the blob's `open` call. The writer's default write keyword arguments are merged with the supplied ones, with the supplied ones taking precedence. The default write keyword arguments include `ignore_flush=True`.
- When `min_part_size` is supplied, it is used as the multipart upload chunk size for the blob.
- The public function `smart_open.gcs.open(bucket_id, blob_id, mode, buffer_size=None, min_part_size=None, client=None, blob_properties=None, blob_open_kwargs=None)` opens a GCS object for reading or writing.
  - Read modes `'rb'` and `'r'` return a binary file-like object obtained by opening the blob with its `open('rb', ...)` method, forwarding `blob_open_kwargs`.
  - Write modes `'wb'` and `'w'` return the writer described above.
  - Supplying `buffer_size` emits a warning that names `buffer_size`.
