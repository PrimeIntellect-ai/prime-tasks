Executing commands with sudo
We have searched how heketi can execute commands with sudo and found an implementation error. In the Issue #299 the sudo was removed from the commands which is great, but the [ssh.go](https://github.com/heketi/heketi/blob/255ff7a68de06d3016379817c213a9875c66107f/pkg/utils/ssh/ssh.go) **ConnectAndExec** function has still the issue that it runs a bash with the sudo command **(it becomes root!!!)**

```
[HIDDEN]
```
so as you can see every command is executed with root priviliges in bash. Maybe the fault happened here #427

[HIDDEN] So that you can unlock these commands with visudo under /etc/sudoers.d/heketi

```
Cmnd_Alias HEKETI_CMDS = /bin/mkdir, /bin/rmdir, /bin/mount, /bin/umount, /sbin/mkfs.xfs, /bin/sed, /sbin/lvs, /sbin/pvcreate, /sbin/pvremove, /sbin/vgcreate,/sbin/vgremove, /sbin/vgdisplay, /sbin/lvcreate, /sbin/lvremove, /usr/sbin/gluster

heketi  ALL=(ALL:ALL)NOPASSWD: HEKETI_CMDS
```

and everything will be fine!
Thanks a lot for the great work you did...

### Additional contract requirements

- When sudo is enabled, the requested command must run with elevated privileges without running the shell itself with elevated privileges.
