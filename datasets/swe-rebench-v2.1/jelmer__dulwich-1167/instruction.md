`iterobjects_subset` not working
Continuing the discussion from here https://github.com/jonashaag/klaus/pull/310

```
In [1]: import dulwich.repo

In [2]: repo = dulwich.repo.Repo("nixpkgs.git")

In [3]: next(repo.object_store.iterobjects_subset([repo[b"HEAD"].id]))
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
Cell In[3], line 1
----> 1 next(repo.object_store.iterobjects_subset([repo[b"HEAD"].id]))

File .../dulwich/object_store.py:604, in PackBasedObjectStore.iterobjects_subset(self, shas, allow_missing)
    602     yield o
    603 elif not allow_missing:
--> 604     raise KeyError(oid)

KeyError: b'5804b7fb5fa07ac9b3720a19aa207edfb1521133'

In [4]: repo[repo[b"HEAD"].id]
Out[4]: <Commit b'5804b7fb5fa07ac9b3720a19aa207edfb1521133'>

In [5]: dulwich.__version__
Out[5]: (0, 21, 3)
```
