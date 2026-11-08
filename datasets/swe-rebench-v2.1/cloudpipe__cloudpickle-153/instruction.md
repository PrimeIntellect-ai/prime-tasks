cloudpickle can produce incorrect pickles
```
>>> import multiprocessing as mp, cloudpickle, pickletools
>>> v = mp.Value('i')
>>> cloudpickle.dumps(v)
b'\x80\x02'
>>> import pickletools
>>> pickletools.dis(cloudpickle.dumps(v))
    0: \x80 PROTO      2
Traceback (most recent call last):
  File "<ipython-input-28-9e637ba398b4>", line 1, in <module>
    pickletools.dis(cloudpickle.dumps(v))
  File "/home/antoine/miniconda3/envs/dask36/lib/python3.6/pickletools.py", line 2398, in dis
    for opcode, arg, pos in genops(pickle):
  File "/home/antoine/miniconda3/envs/dask36/lib/python3.6/pickletools.py", line 2238, in _genops
    raise ValueError("pickle exhausted before seeing STOP")
ValueError: pickle exhausted before seeing STOP
```

### Additional contract requirements

When cloudpickle cannot serialize an object, it must report the failure rather than return partial or malformed pickle bytes as a successful result.
