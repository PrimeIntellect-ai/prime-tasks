machine object does not contain resource_pool information
When looking at the returned machine object, it does not contain the resource pool information.

```
>>> dir(machines_list[0])
['__class__', '__delattr__', '__dir__', '__doc__', '__eq__', '__format__', '__ge__', '__getattribute__', '__gt__', '__hash__', '__init__', '__init_subclass__', '__le__', '__lt__', '__module__', '__ne__', '__new__', '__reduce__', '__reduce_ex__', '__repr__', '__setattr__', '__sizeof__', '__slots__', '__str__', '__subclasshook__', '__weakref__', '_changed_data', '_data', '_handler', '_loaded', '_orig_data', '_origin', 'abort', 'architecture', 'as_device', 'as_machine', 'as_rack_controller', 'as_region_controller', 'bcaches', 'block_devices', 'boot_disk', 'boot_interface', 'cache_sets', 'clear_default_gateways', 'commission', 'cpus', 'deploy', 'disable_ipv4', 'distro_series', 'enter_rescue_mode', 'exit_rescue_mode', 'fqdn', 'get_curtin_config', 'get_details', 'get_power_parameters', 'hostname', 'hwe_kernel', 'interfaces', 'ip_addresses', 'loaded', 'mark_broken', 'mark_fixed', 'memory', 'min_hwe_kernel', 'netboot', 'node_type', 'osystem', 'owner', 'owner_data', 'power_off', 'power_on', 'power_state', 'power_type', 'query_power_state', 'raids', 'refresh', 'release', 'restore_default_configuration', 'restore_networking_configuration', 'restore_storage_configuration', 'save', 'status', 'status_action', 'status_message', 'status_name', 'system_id', 'tags', 'volume_groups', 'zone']
```

However, when I use the 'maas' client on the maas region controller, I see the 'pool' information is added to the machine.

```
"pool": {
            "name": "test_pool_1",
            "description": "",
            "id": 1,
            "resource_uri": "/MAAS/api/2.0/resourcepool/1/"
        },
```

How can I get the list of machines in a resource pool using the python-libmaas library ?

Thanks,

### Additional contract requirements

- `maas.client.viscera.nodes.Node` exposes the node's resource pool through a public `pool` attribute. Reading a node whose data contains a resource pool yields a `maas.client.viscera.resource_pools.ResourcePool` object for that attribute.
- The `pool` attribute accepts a `maas.client.viscera.resource_pools.ResourcePool` instance.
- `maas.client.viscera.nodes.Node.save()` persists changes to the node. When the node's resource pool has been changed, the resource pool is sent to the API by name.
