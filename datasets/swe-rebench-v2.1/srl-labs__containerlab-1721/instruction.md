Use `unbound` ssh option only for ssh clients supporting it.
When we started to use unbound option to mitigate SR OS SSH server not understanding modern ssh options we started to do this for all systems.

But apparently picky ssh clients bail out when they see unbound value being used which they don't recognize:

```
ssh -l admin clab-nc-sr1
/etc/ssh/ssh_config.d/clab-nc.conf line 6: unsupported option "unbound".

ssh -V
OpenSSH_8.0p1, OpenSSL 1.1.1k  FIPS 25 Mar 2021
```

I think we need to
[HIDDEN]
3. and only set it for clients newer than the release that first started to support this option.

## OpenSSH version

OpenSSH version 8.9 is the first release where unbound option is supported:


```
OpenSSH_8.8p1, OpenSSL 1.1.1v  1 Aug 2023 - does not work
```

```
OpenSSH_8.9p1 Ubuntu-3ubuntu0.3, OpenSSL 3.0.2 15 Mar 2022 - works
```

```
OpenSSH_9.0p1, OpenSSL 1.1.1v  1 Aug 2023 - works
```

### Additional contract requirements

- OpenSSH 8.9 is the first client version that supports the `unbound` value; the `unbound` value must be used for OpenSSH 8.9 and newer, and omitted for older versions.
- When the SSH client version cannot be determined, the `unbound` value must be omitted.
