`huggingface-cli upload` - `_wrapped_lfs_upload` should retry | `http_backoff` retry not working with `_upload_multi_part`/`SliceFileObj`
```
HTTP Error 500 thrown while requesting PUT https://hf-hub-lfs-us-east-1.s3-accelerate.amazonaws.com/repos/...
Traceback (most recent call last):
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/utils/_http.py", line 405, in hf_raise_for_status
    response.raise_for_status()
  File "/usr/local/lib/python3.9/site-packages/requests/models.py", line 1024, in raise_for_status
    raise HTTPError(http_error_msg, response=self)
requests.exceptions.HTTPError: 400 Client Error: Bad Request for url: https://huggingface.co/api/complete_multipart...
The above exception was the direct cause of the following exception:
Traceback (most recent call last):
File "/usr/local/lib/python3.9/site-packages/huggingface_hub/_commit_api.py", line 431, in _wrapped_lfs_upload
lfs_upload(operation=operation, lfs_batch_action=batch_action, headers=headers, endpoint=endpoint)
File "/usr/local/lib/python3.9/site-packages/huggingface_hub/lfs.py", line 246, in lfs_upload
_upload_multi_part(operation=operation, header=header, chunk_size=chunk_size, upload_url=upload_url)
File "/usr/local/lib/python3.9/site-packages/huggingface_hub/lfs.py", line 355, in _upload_multi_part
hf_raise_for_status(completion_res)
File "/usr/local/lib/python3.9/site-packages/huggingface_hub/utils/_http.py", line 459, in hf_raise_for_status
 raise _format(BadRequestError, message, response) from e
 huggingface_hub.errors.BadRequestError: (Request ID: Root=1-66e43174-2ebfb55456eac7aa1735c83b;cb20fa6b-0659-47af-8f62-2698e507c12b)
Bad request:
   Your proposed upload is smaller than the minimum allowed size
The above exception was the direct cause of the following exception:
File "/usr/local/lib/python3.9/site-packages/huggingface_hub/commands/huggingface_cli.py", line 57, in main
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/commands/huggingface_cli.py", line 57, in main
    service.run()
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/commands/upload.py", line 192, in run
    print(self._upload())
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/commands/upload.py", line 287, in _upload
    return self.api.upload_folder(
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/utils/_validators.py", line 114, in _inner_fn
    return fn(*args, **kwargs)
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/hf_api.py", line 1473, in _inner
    return fn(self, *args, **kwargs)
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/hf_api.py", line 4990, in upload_folder
    commit_info = self.create_commit(
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/utils/_validators.py", line 114, in _inner_fn
    return fn(*args, **kwargs)
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/hf_api.py", line 1473, in _inner
    return fn(self, *args, **kwargs)
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/hf_api.py", line 3901, in create_commit
    self.preupload_lfs_files(
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/hf_api.py", line 4448, in preupload_lfs_files
    _upload_lfs_files(
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/utils/_validators.py", line 114, in _inner_fn
    return fn(*args, **kwargs)
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/_commit_api.py", line 446, in _upload_lfs_files
    thread_map(
  File "/usr/local/lib/python3.9/site-packages/tqdm/contrib/concurrent.py", line 69, in thread_map
    return _executor_map(ThreadPoolExecutor, fn, *iterables, **tqdm_kwargs)
  File "/usr/local/lib/python3.9/site-packages/tqdm/contrib/concurrent.py", line 51, in _executor_map
    return list(tqdm_class(ex.map(fn, *iterables, chunksize=chunksize), **kwargs))
  File "/usr/local/lib/python3.9/site-packages/tqdm/std.py", line 1181, in __iter__
    for obj in iterable:
  File "/usr/lib64/python3.9/concurrent/futures/_base.py", line 609, in result_iterator
    yield fs.pop().result()
  File "/usr/lib64/python3.9/concurrent/futures/_base.py", line 446, in result
    return self.__get_result()
  File "/usr/lib64/python3.9/concurrent/futures/_base.py", line 391, in __get_result
    raise self._exception
  File "/usr/lib64/python3.9/concurrent/futures/thread.py", line 58, in run
    result = self.fn(*self.args, **self.kwargs)
  File "/usr/local/lib/python3.9/site-packages/huggingface_hub/_commit_api.py", line 433, in _wrapped_lfs_upload
    raise RuntimeError(f"Error while uploading '{operation.path_in_repo}' to the Hub.") from exc
RuntimeError: Error while uploading 'part-00537.parquet' to the Hub.
```

Using huggingface_hub@main([3cd3286](https://github.com/huggingface/huggingface_hub/commit/3cd32863bdee76e80117ae2d05eeba68045e75e1))

This issue wastes hours hashing files again. As a side note implementing the caching of `upload-large-folder` path for `upload` would be useful, I find `upload-large-folder` to be unsuitable as it hits API rate limits by creating too many commits, the number of commits in turn affects Dataset Viewer, and in my testing passing `--revision` to `upload-large-folder` gives errors on upload.

With regards to this particular issue [HIDDEN], which seems to be caused by transient S3 errors, something like:
```
[HIDDEN]
```

### Additional contract requirements

- `http_backoff` must retry a request when the response status code is in `retry_on_status_codes` (or an exception in `retry_on_exceptions` is raised).
- When the request `data` is a seekable file-like object, including a `SliceFileObj` (importable from `huggingface_hub.lfs`), the full content must be re-sent on every retry attempt rather than an exhausted/empty stream.
- A transient failure on an LFS upload request must be retried rather than immediately aborting the upload.
