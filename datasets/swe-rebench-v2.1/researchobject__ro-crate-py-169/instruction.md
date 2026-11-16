Entity id should not be modifiable
It's used to index the entity in the crate's `__entity_map`, so changing it leads to inconsistencies:

```pycon
>>> from rocrate.rocrate import ROCrate
>>> crate = ROCrate()
>>> d = crate.add_dataset("FOO")
>>> crate._ROCrate__entity_map
{..., 'arcp://uuid,2f145cc1-20be-4cd7-ac86-d6d4a08cdcf9/FOO': <FOO/ Dataset>}
>>> d.id = "foo"
>>> crate._ROCrate__entity_map
{..., 'arcp://uuid,2f145cc1-20be-4cd7-ac86-d6d4a08cdcf9/FOO': <foo Dataset>}
>>> crate.dereference("foo")
>>> crate.dereference("FOO")
<foo Dataset>

```
