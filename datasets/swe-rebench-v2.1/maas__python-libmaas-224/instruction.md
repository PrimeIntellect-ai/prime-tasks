Cannot create LVM logical volumes
## Environment
python-libmaas==0.6.1
Python 3.6.7

## Problem
There is no way to create logical volumes (LVs) over a Volume Group (VG). The `create()` function fails: `TypeError: node must be a Node or str, not VolumeGroup`

## Steps to reproduce
```python
In [102]: vgs = machine.volume_groups

In [103]: vgs
Out[103]: <VolumeGroups.Managed#Machine length=1 items=[<VolumeGroup id=9 node=<Node system_id='y4ewhb' (unloaded)> (unloaded)>]>

In [104]: vg = vgs[0]

In [105]: vg
Out[105]: <VolumeGroup id=9 node=<Node system_id='y4ewhb' (unloaded)> (unloaded)>

In [106]: vg.refresh()

In [107]: vg
Out[107]: <VolumeGroup name='vg0' size=1197754810368>

In [108]: vglvs = vg.logical_volumes

In [109]: vglvs
Out[109]: <BlockDevices.Managed#VolumeGroup length=0 items=[]>

In [110]: vglvs.create('test')
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
<ipython-input-119-feb8a4bf62ec> in <module>
----> 1 vglvs.create('test')

~/myproject/lib/python3.6/site-packages/maas/client/utils/async.py in wrapper(*args, **kwargs)
     47         if not eventloop.is_running():
     48             while isawaitable(result):
---> 49                 result = eventloop.run_until_complete(result)
     50         return result
     51

/usr/lib/python3.6/asyncio/base_events.py in run_until_complete(self, future)
    471             raise RuntimeError('Event loop stopped before Future completed.')
    472
--> 473         return future.result()
    474
    475     def stop(self):

~/myproject/lib/python3.6/site-packages/maas/client/viscera/__init__.py in _create(self, *args, **kwargs)
    503         if manager is not None and manager_field is not None:
    504             args = (manager,) + args
--> 505             new_obj = await super_cls.create(*args, **kwargs)
    506             self._items = self._items + [new_obj]
    507             manager._data[manager_field.name] = (

~/myproject/lib/python3.6/site-packages/maas/client/viscera/block_devices.py in create(cls, node, name, model, serial, id_path, size, block_size, tags)
    206             raise TypeError(
    207                 'node must be a Node or str, not %s' % (
--> 208                     type(node).__name__))
    209
    210         if not size or size < 0:

TypeError: node must be a Node or str, not VolumeGroup

```

### Additional contract requirements

Add a public class `LogicalVolume` and a public class `LogicalVolumes` in the
module `maas.client.viscera.logical_volumes`.

`LogicalVolumes.create(cls, volume_group, name, size, *, uuid=None, tags=None)`
creates a logical volume on the given volume group and returns a `LogicalVolume`
object. `volume_group` is a `VolumeGroup`; `name` is a non-empty string; `size`
is a positive integer number of bytes; `uuid` is an optional string; `tags` is
an optional iterable of strings to add after creation. It raises `TypeError` if
`volume_group` is not a `VolumeGroup`, and raises `ValueError` if `name` is
falsy or `size` is less than or equal to zero.

`LogicalVolume.__repr__(self)` returns a string of the form
`<LogicalVolume name='<name>'>`, showing only the name.

A volume group's `logical_volumes` collection must allow creation for that
owning volume group.
