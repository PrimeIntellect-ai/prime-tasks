_motifs max_matches=None bug
When finding motifs, the function encounters a bug when `max_matches` is set to `None` to not restrict the number of matches. [HIDDEN]

Example:
```
>>> import numpy as np
>>> import stumpy
>>> arr = np.array([0.,1,2,2,0,1,2,2,0,0,0,0])
>>> mp = stumpy.stump(arr, m=3)
>>> stumpy.motifs(arr, mp[:,0], max_matches=None)
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/user0/code/venv/lib/python3.10/site-packages/stumpy/core.py", line 138, in inner_wrapper
    return norm(*args, **kwargs)
  File "/Users/user0/code/venv/lib/python3.10/site-packages/stumpy/motifs.py", line 361, in motifs
    motif_distances, motif_indices = _motifs(
  File "/Users/user0/code/venv/lib/python3.10/site-packages/stumpy/motifs.py", line 134, in _motifs
    motif_distances.append(query_matches[:max_matches, 0])
TypeError: slice indices must be integers or None or have an __index__ method
```
