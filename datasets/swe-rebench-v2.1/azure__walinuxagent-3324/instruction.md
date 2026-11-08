[BUG][RHEL-9] Failed to decrypt certificate if FIPS is enabled
**Describe the bug: A clear and concise description of what the bug is.**
In RHEL-9, if use WALA as provision agent(no cloud-init) and FIPS is enabled in the image, the VM provision failed because `Failed to decrypt /var/lib/waagent/Certificates.p7m`.
```
2022-05-31T09:24:07.349895Z VERBOSE Daemon Daemon HTTP connection [GET] [/machine/40519e2d-4b98-4175-983a-277dc2f49e03/fadb1d67%2Dc46a%2D4f7e%2D9fe6%2D5aca4e50cbb2.%5Fwala9fips%2Dwala3?comp=config&type=sharedConfig&incarnation=1] [None] [{'x-ms-agent-name': 'WALinuxAgent', 'x-ms-version': '2012-11-30', 'Connection': 'close', 'User-Agent': 'WALinuxAgent/2.7.0.6'}]
2022-05-31T09:24:07.385196Z VERBOSE Daemon Daemon [HTTP Response] Status Code 200
2022-05-31T09:24:07.395768Z VERBOSE Daemon Daemon HTTP connection [GET] [/machine/40519e2d-4b98-4175-983a-277dc2f49e03/fadb1d67%2Dc46a%2D4f7e%2D9fe6%2D5aca4e50cbb2.%5Fwala9fips%2Dwala3?comp=certificates&incarnation=1] [None] [{'x-ms-agent-name': 'WALinuxAgent', 'x-ms-version': '2012-11-30', 'x-ms-cipher-name': 'DES_EDE3_CBC', 'x-ms-guest-agent-public-x509-cert': 'MIIDEzCCAfugAwIBAgIUQ5M9PIMiW61BsE2EmkX5Yfy1WnkwDQYJKoZIhvcNAQELBQAwGTEXMBUGA1UEAwwOTGludXhUcmFuc3BvcnQwHhcNMjIwNTMxMDkyNDA3WhcNMjQwNTMwMDkyNDA3WjAZMRcwFQYDVQQDDA5MaW51eFRyYW5zcG9ydDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANzUBQ6YgxQ/8bW1VXzpRG5Gz8iNico1zT29q7BJ6YiUXqi//fQIhH7xrp07zYFnAnw4I3Vbe8FtygAof/78f+7PSQO+cWG7XS8iea3A+E3/y+fma2eVJJk0RC98gtJuuoQ8spn9vwMpbSQZMtOJp8jGlq+tRCIKttl0ogR6VF+zQp6VFCbgWRMe/1gUe7S+x72d72et93U09kmIdaK3v6qlszZsSNk0gCxp/nkqD545eCXvITCGWarqjTJZfwNtXfT9ZP0zry3yC326xw7IPw80w2lCHR+4+YafFST1XTildI+AopsPMVS9jZVLUnESUHrNZ1bS7D+jMniG5ctGl7ECAwEAAaNTMFEwHQYDVR0OBBYEFE4GKfSQxuVvFnAyvednFTdSyBXwMB8GA1UdIwQYMBaAFE4GKfSQxuVvFnAyvednFTdSyBXwMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAG2dKGJAsJm7NsNOHk1s2O7OgfabsWpq/lrGi+D+EKfXRqtdGl0m3IB1v4DEVNgoBEsVMD+oJD23Bihef2TKLtwt9Llqna7o5aq9jVFZ8Rp57gS+WpBpf37aqtIBIIplIW0TouUx77Zo0o2abv7rn7XsJUl6vblk8xnKtWYAGn9WEAZki6tVM2P0jUBqYgCAg4b4+FthJA2/weYSUNRfgfjxE4bTLdvJPBs3oV/J/BbmPbf7zurqeru8x7AnbZgUV14xwhrQXkn1pl2JF1wHJb/sJ8qlAVzOqHrnenHTCSsdVArJkWso5bgvbYnJ2k38GUaWQyfmQ2NPHhuhKIs27a0=', 'Connection': 'close', 'User-Agent': 'WALinuxAgent/2.7.0.6'}]
2022-05-31T09:24:07.493235Z VERBOSE Daemon Daemon [HTTP Response] Status Code 200
2022-05-31T09:24:07.642123Z ERROR Daemon Daemon Failed to decrypt /var/lib/waagent/Certificates.p7m (return code: 1)
[stdout]

[stderr]
Error decrypting CMS structure
80DB9D812D7F0000:error:0308010C:digital envelope routines:inner_evp_generic_fetch:unsupported:crypto/evp/evp_fetch.c:349:Global default library context, Algorithm (DES-EDE3-CBC : 27), Properties ()
80DB9D812D7F0000:error:17000065:CMS routines:ossl_cms_EncryptedContent_init_bio:cipher initialisation error:crypto/cms/cms_enc.c:78:
```

**Distro and WALinuxAgent details (please complete the following information):**
 - Distro and Version: RHEL-9.1
 - openssl-3.0.1-27.el9_0.x86_64
 - WALinuxAgent version:
 ```
WALinuxAgent-2.7.0.6 running on rhel 9.1
Python: 3.9.10
Goal state agent: 2.7.0.6
```

**Steps**
1. Create a RHEL-9 VM on Azure. Enable FIPS(`fips-mode-setup --enable`). Remove cloud-init package. Set OS.EnableFIPS=y in /etc/waagent.conf
2. Deprovision it as a generalized image
3. Create a new VM from this image

**Log file attached**
If possible, please provide the full /var/log/waagent.log file to help us understand the problem better and get the context of the issue.
[waagent.log](https://github.com/Azure/WALinuxAgent/files/8803950/waagent.log)

### Additional contract requirements

- To address the FIPS 140-3 failure, the certificates must be requested from the WireServer using the `AES128_CBC` cipher, and the legacy `DES_EDE3_CBC` cipher must also be attempted as a fallback. The order in which the two ciphers are attempted is not significant.
- `LogEvent.error(op, fmt, *args)` writes the formatted message to the underlying logger at error level and records a telemetry event via `add_event` with `is_success=False` and `log_event=False`.
