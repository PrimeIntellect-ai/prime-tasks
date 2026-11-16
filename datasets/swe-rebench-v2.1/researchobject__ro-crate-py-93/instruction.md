Adding a directory to a new crate gives an error when trying to write the crate: AttributeError: 'str' object has no attribute 'exists'
Adding a directory to a new crate gives an error when trying to write the crate: `AttributeError: 'str' object has no attribute 'exists'`

See the below example:

```python
import os
from rocrate.rocrate import ROCrate
crate = ROCrate()
os.makedirs("tmp3", exist_ok=True)
dataset_entity = crate.add_directory(source="tmp3", dest_path="new_tmp")
crate.write("./new_crate4")
```

```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
/tmp/ipykernel_9363/134362041.py in <module>
      4 open('tmp3/empty_file', 'w').close()
      5 dataset_entity = crate.add_directory(source="tmp", dest_path="new_tmp")
----> 6 crate.write("./new_crate3")

~/Downloads/Elixir/ro-crate-py/rocrate/rocrate.py in write(self, base_path)
    473             self._copy_unlisted(self.source, base_path)
    474         for writable_entity in self.data_entities + self.default_entities:
--> 475             writable_entity.write(base_path)
    476
    477     write_crate = write  # backwards compatibility

~/Downloads/Elixir/ro-crate-py/rocrate/model/dataset.py in write(self, base_path)
     49         else:
     50             out_path.mkdir(parents=True, exist_ok=True)
---> 51             [HIDDEN]
     52                 self.crate._copy_unlisted(self.source, out_path)
     53

AttributeError: 'str' object has no attribute 'exists'
```

### Additional contract requirements

- When a directory is added to a new crate using a string filesystem path as `source`, writing the crate must complete without the reported `AttributeError` and include that directory at its destination path in the written crate.
