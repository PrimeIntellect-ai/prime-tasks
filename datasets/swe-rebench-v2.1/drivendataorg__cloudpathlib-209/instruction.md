Calling `.suffix` on a dir raises IndexError
`Path("/dir").suffix` returns the empty string, and we should do the same.


`S3Path("s3://bucket/dir").suffix` results in:

```python
---------------------------------------------------------------------------
IndexError                                Traceback (most recent call last)
<ipython-input-21-161bf2e9d1ca> in <module>
----> 1 S3Path("s3://bucket/dir").suffix

~/miniconda3/envs/zamba-algorithms/lib/python3.6/site-packages/cloudpathlib/cloudpath.py in suffix(self)
    522     @property
    523     def suffix(self):
--> 524         return self._dispatch_to_path("suffix")
    525
    526     @property

~/miniconda3/envs/zamba-algorithms/lib/python3.6/site-packages/cloudpathlib/cloudpath.py in _dispatch_to_path(self, func, *args, **kwargs)
    470
    471         if isinstance(path_version, collections.abc.Sequence) and isinstance(
--> 472             [HIDDEN]
    473         ):
    474             return [

IndexError: string index out of range



```
