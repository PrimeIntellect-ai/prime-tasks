Ability to read COPC from fsspec sources
Sometimes I'll read laz files via fsspec (`s3fs` or `gcsfs`):
```python
import laspy
import s3fs

fs = s3fs.S3FileSystem()
with fs.open("s3://bucket/object.laz") as fh:
    with laspy.open(fh) as las_fh:
        # do things
```
However, for COPC files `CopcReader.open` only takes local/http strings.

I was able to get something working this way:
```patch
diff --git a/laspy/copc.py b/laspy/copc.py
index efdcb66..5a23d1b 100644
--- a/laspy/copc.py
+++ b/laspy/copc.py
@@ -642,7 +642,7 @@ class CopcReader:
     @classmethod
     def open(
         cls,
-        uri: str,
+        uri: Union[str, io.IOBase],
         http_num_threads: int = DEFAULT_HTTP_WORKERS_NUM,
         _http_strategy: str = "queue",
         decompression_selection: DecompressionSelection = DecompressionSelection.all(),
@@ -693,11 +693,13 @@ class CopcReader:
         .. versionadded:: 2.4
             The ``decompression_selection`` parameter.
         """
[HIDDEN]

         return cls(
             source,
```

I'm not sure if the `io.IOBase` check is very thorough or not, but happy to put into PR and add tests if this is a good start.

### Additional contract requirements

- `laspy.CopcReader.open` is a class method on `laspy.copc.CopcReader`. Its first
  parameter accepts a string path, an HTTP/HTTPS URL, an `os.PathLike` object, or a
  file-like object implementing `io.IOBase` (for example an fsspec handle).
- When the Lazrs backend is unavailable, `laspy.CopcReader.open` raises
  `laspy.errors.LazError`.
