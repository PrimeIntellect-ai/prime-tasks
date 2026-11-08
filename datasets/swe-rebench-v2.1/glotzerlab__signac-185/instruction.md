Error when storing NumPy arrays in job document.
### Description

Trying to save a NumPy array to the job document fails after loading the job document back (e.g. when adding another key or printing its contents).

### To reproduce

```python
import signac
import numpy as np

project = signac.init_project('dfs-update-bug')
for job in project:
    job.remove()
job = project.open_job({'a': 0})
job.init()
job.doc.my_array = np.array([0, 1, 2])
print(job.doc)
```

### Error output

```python
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
<ipython-input-1-4f94befa8a51> in <module>
      7 job = project.open_job({'a': 0}).init()
      8 job.doc.my_array = np.array([0, 1, 2])
----> 9 print(job.doc)

~/code/signac/signac/core/synceddict.py in __str__(self)
    264
    265     def __str__(self):
--> 266         return str(self())
    267
    268     def _as_dict(self):

~/code/signac/signac/core/synceddict.py in __call__(self)
    271
    272     def __call__(self):
--> 273         self._synced_load()
    274         return self._as_dict()
    275

~/code/signac/signac/core/synceddict.py in _synced_load(self)
    157
    158     def _synced_load(self):
--> 159         self.load()
    160
    161     def load(self):

~/code/signac/signac/core/synceddict.py in load(self)
    165                 if data is not None:
    166                     with self._suspend_sync():
--> 167                         self._dfs_update(self._data, data)
    168                     for value in self._data:
    169                         if isinstance(value, Mapping):

~/code/signac/signac/core/synceddict.py in _dfs_update(self, old, new)
    143         for key in new:
    144             if key in old:
--> 145                 if old[key] == new[key]:
    146                     continue
    147                 elif isinstance(new[key], Mapping) and isinstance(old[key], Mapping):

ValueError: The truth value of an array with more than one element is ambiguous. Use a.any() or a.all()
```

### System configuration

Please complete the following information:

 - Operating System: Linux-4.4.0-17134-Microsoft-x86_64-with-debian-buster-sid
 - Version of Python: 3.6.8 |Anaconda, Inc.| (default, Dec 30 2018, 01:22:34) [GCC 7.3.0]
 - Version of signac: 1.0.0 (current `master`)
