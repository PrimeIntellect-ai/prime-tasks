Ensure re-instantiation is idempotent
One of my favorite things about `Path` is that it is idempotent, and that means that I can easily handle string or `PathLike` input by just doing `p = Path(p)` at top of my function. This seems to work in the basic case:

```
In [1]: from cloudpathlib import CloudPath

In [2]: c = CloudPath('s3://test/test.txt')

In [3]: CloudPath(c)
Out[3]: S3Path('s3://test/test.txt')
```

We should make sure that `CloudPath` does the same (maybe it already does?) by at least adding some tests. I'm not sure it is truly idempotent and will use the same client if a new one is not passed, etc., etc.
