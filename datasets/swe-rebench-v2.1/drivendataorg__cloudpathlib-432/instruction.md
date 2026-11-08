Instantiate default client lazily
Hi!

I've refactored my code and moved from [s3path](https://github.com/liormizr/s3path) to `cloudpathlib` to support S3 and GCS backends. Everything works great except that clients are created in constructors, possibly when credentials are not yet available.

Here's an example:

```python
from cloudpathlib import S3Path
from dotenv import load_dotenv

UPLOADS_PATH = S3Path("s3://my-bucket/uploads")


def main():
    load_dotenv()
    UPLOADS_PATH.exists()  # <--- botocore.exceptions.NoCredentialsError: Unable to locate credentials


if __name__ == "__main__":
    main()
```

If I call `load_dotenv` before defining `UPLOADS_PATH` it works, but that's not a good practice.

I worked around this by making them functions:

```python
@cache
def UPLOADS_PATH() -> S3Path:
    return S3Path("s3://my-bucket/uploads")
```

but it is an extra boilerplate and also requires changes to the code.

Would it be possible to delay the instantiation of the client class, e.g. to the moment of the first call that actually requires it? I think this is the way it works in `s3path` since it worked for me for a very long time.
