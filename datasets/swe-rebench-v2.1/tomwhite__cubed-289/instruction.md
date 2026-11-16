Bugs with passing allowed_mem as a string
There are some bugs with #188

```python
In [2]: cubed.Spec(allowed_mem='0.8MB')
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[2], line 1
----> 1 cubed.Spec(allowed_mem='0.8MB')

File ~/Documents/Work/Code/cubed/cubed/core/array.py:261, in Spec.__init__(self, work_dir, max_mem, allowed_mem, reserved_mem, executor, storage_options)
    259     self._allowed_mem = (max_mem or 0) + self.reserved_mem
    260 else:
--> 261     self._allowed_mem = convert_to_bytes(allowed_mem)
    263 self._executor = executor
    264 self._storage_options = storage_options

File ~/Documents/Work/Code/cubed/cubed/utils.py:216, in convert_to_bytes(size)
    214     value = size[:-2]
    215 else:
--> 216     raise ValueError(
    217         f"Invalid value: {size}. Expected a string ending with an SI prefix."
    218     )
[HIDDEN]

ValueError: Invalid value: 0.8MB. Expected a string ending with an SI prefix.

In [10]: cubed.Spec(allowed_mem='8 MB')
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
Cell In[10], line 1
----> 1 cubed.Spec(allowed_mem='8 MB')

File ~/Documents/Work/Code/cubed/cubed/core/array.py:261, in Spec.__init__(self, work_dir, max_mem, allowed_mem, reserved_mem, executor, storage_options)
    259     self._allowed_mem = (max_mem or 0) + self.reserved_mem
    260 else:
--> 261     self._allowed_mem = convert_to_bytes(allowed_mem)
    263 self._executor = executor
    264 self._storage_options = storage_options

File ~/Documents/Work/Code/cubed/cubed/utils.py:216, in convert_to_bytes(size)
    214     value = size[:-2]
    215 else:
--> 216     raise ValueError(
    217         f"Invalid value: {size}. Expected a string ending with an SI prefix."
    218     )
[HIDDEN]

ValueError: Invalid value: 8 MB. Expected a string ending with an SI prefix.
```

### Additional contract requirements

When `Spec` receives `allowed_mem` as a string, it must accept decimal-valued SI-prefixed quantities such as `0.8MB` and quantities with whitespace between the value and SI unit such as `8 MB`, interpreting each as a byte quantity.
