mtu can't bet set
### Steps to reproduce

```
tw-ww4:~ # wwctl node set n01 --netname=default --mtu 1200
ERROR: strconv.ParseUint: parsing "": invalid syntax
```

### Error message

```
tw-ww4:~ # wwctl node set n01 --netname=default --mtu 1200
ERROR: strconv.ParseUint: parsing "": invalid syntax
```

### Information on your system

wwctl version:	 4.5.x-1
rpc version: apiPrefix:"rc1"  apiVersion:"1"  warewulfVersion:"4.5.x-1"


### General information

- [X] I have run `wwctl version` and reported the contents of `/etc/os-release`
- [X] I have searched the issues of this repo and believe this is not a duplicate
- [X] I have captured and reported relevant error messages and logs
