Unable to load containers after devices.Type change
Just found this today:

[root@kir-rhat runc-tst]# ../runc/runc list
load container cc6: json: cannot unmarshal number into Go struct field Device.config.devices.type of type devices.Type
ID          PID         STATUS      BUNDLE      CREATED     OWNER

@thaJeztah not sure if there's a way to work around that -- if not, we may need to revert  https://github.com/opencontainers/runc/pull/3159

### Additional contract requirements

- Loading a container whose persisted configuration records device types in the numeric form written by older runc versions must succeed. Decoding such a persisted configuration must not fail, and each decoded device must carry the device type denoted by the persisted value (for example, the value persisted for a block device must decode to the block device type).
