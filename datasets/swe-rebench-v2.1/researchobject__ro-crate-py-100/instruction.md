Can't read recent WorkflowHub crates
Reported by @lrodrin and @jmfernandez at yesterday's community meeting. One such example is https://workflowhub.eu/workflows/244.

```pycon
>>> from rocrate.rocrate import ROCrate
>>> crate = ROCrate("/tmp/workflow-244-3")
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/simleo/git/ro-crate-py/rocrate/rocrate.py", line 90, in __init__
    source = self.__read(source, gen_preview=gen_preview)
  File "/home/simleo/git/ro-crate-py/rocrate/rocrate.py", line 132, in __read
    self.__read_data_entities(entities, source, gen_preview)
  File "/home/simleo/git/ro-crate-py/rocrate/rocrate.py", line 177, in __read_data_entities
    metadata_id, root_id = self.find_root_entity_id(entities)
  File "/home/simleo/git/ro-crate-py/rocrate/rocrate.py", line 150, in find_root_entity_id
    [HIDDEN]
AttributeError: 'list' object has no attribute 'startswith'

```
