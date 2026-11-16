Setting/Accessing nested properties on entities without @id
RO-Crates aim to write the metadata file as flattend and compacted JSON-LD. I have noticed some inconsistencies with enforcing this behavior in this library.

Currently, it is possible to write nested properties to an entity, even if this property is a dictionary that does not contain an `@id`. Here is an example:

```python
from rocrate.rocrate import ROCrate

crate = ROCrate()

# setting a nested property throws no error
crate.root_dataset["license"] = {
    "@type": "CreativeWork",
    "name": "CC-O",
    "url": "https://spdx.org/licenses/CC0-1.0"
}

crate.write("mycrate")
```

While the crate is written to disk without errors, attempting to access such a nested property once set from an ROCrate object raises an exception:
```python
crate.root_dataset["license"]
```
raises:
```bash
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
File ~/projects/playground/venv/lib/python3.12/site-packages/rocrate/model/entity.py:91, in Entity.__getitem__(self, key)
     90 try:
---> 91     id_ = entry["@id"]
     92 except KeyError:

KeyError: '@id'

During handling of the above exception, another exception occurred:

ValueError                                Traceback (most recent call last)
Cell In[32], line 1
----> 1 crate.root_dataset["license"]

File ~/projects/playground/venv/lib/python3.12/site-packages/rocrate/model/entity.py:93, in Entity.__getitem__(self, key)
     91     id_ = entry["@id"]
     92 except KeyError:
---> 93     raise ValueError(f"no @id in {entry}")
     94 else:
     95     deref_values.append(self.crate.get(id_, id_))

ValueError: no @id in {'@type': 'CreativeWork', 'name': 'CC-O', 'url': 'https://spdx.org/licenses/CC0-1.0'}
```

To enforce consistency and adhere to the intended behaviour, I suggest to implement a check when assigning a property that makes sure that the `@id` key is present when the property value is a dictionary. It could even be considered to check if the id corresponds to an entity present in the crate.
When accessing values from an RO Crate, it might make sense to be more forgiving and return the property if it has no id or the id does not correspond to an entity.

These changes would prevent the library from creating RO-Crates that cannot be accessed with the very same library afterwards.
