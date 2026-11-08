AttributeError: 'MemoryObjectStore' object has no attribute 'add_pack_data'
Hi,

I just updated from `0.20.50` to `0.21.3` and I'm getting this error now:

```
Traceback (most recent call last):
  #
  # START my code
  #
  File "/Users/xyz/Projects/fs-code/src/codefs/_core.py", line 108, in _delegate
    self.mount(mount_point, self.fetch_archive(ref))
  File "/Users/xyz/Projects/fs-code/src/codefs/gitfs/__init__.py", line 72, in __call__
    result: FetchPackResult = self._client.fetch(self._path, self._repo)  # type: ignore
  #
  # END my code / START dulwich
  #
  File "/Users/xyz/Projects/fs-code/.venv/lib/python3.10/site-packages/dulwich/client.py", line 1456, in fetch
    refs = r.fetch(
  File "/Users/xyz/Projects/fs-code/.venv/lib/python3.10/site-packages/dulwich/repo.py", line 405, in fetch
    target.object_store.add_pack_data(count, pack_data, progress)
  #
  # END dulwich
  #
AttributeError: 'MemoryObjectStore' object has no attribute 'add_pack_data'
```

This is how I'm initializing the repo:
```
# tmp_path is a Path fixture from pytest
porcelain.init(repo := str(tmp_path))
(test_file := tmp_path / "file").write_text("something")
porcelain.add(repo, str(test_file))
porcelain.commit(repo, message="test")
```

Is this a bug?
