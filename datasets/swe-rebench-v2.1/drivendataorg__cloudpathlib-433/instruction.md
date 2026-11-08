[GS] `download_to` with non-existent files don't raise any exception
Version: 0.18.1

Code Example:
```py
from cloudpathlib import CloudPath

# download a non-existent file, in an existing bucket
path = CloudPath("gs://some_existent_bucket/non_existent.txt")
path.download_to(".") # should raise an exception, as the file doesn't exist

# NOTE: trying to download from a non-existing bucket will properly fail
path = CloudPath("gs://non_existent_bucket/foo.txt")
path.download_to(".") # will raise an exception
```
