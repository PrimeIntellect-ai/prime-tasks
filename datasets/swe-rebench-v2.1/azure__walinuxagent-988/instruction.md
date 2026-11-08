Socket timeout causes blacklist
Found in logs, we need to handle this case more gracefully:
```
2017/11/17 11:47:16.626326 WARNING Agent WALinuxAgent-2.2.18 failed with exception: The read operation timed out
2017/11/17 11:47:16.705491 WARNING Traceback (most recent call last):
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/ga/update.py", line 271, in run
    exthandlers_handler.run()
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/ga/exthandlers.py", line 198, in run
    self.handle_ext_handlers(etag)
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/ga/exthandlers.py", line 285, in handle_ext_handlers
    self.handle_ext_handler(ext_handler, etag)
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/ga/exthandlers.py", line 291, in handle_ext_handler
    ext_handler_i.decide_version()
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/ga/exthandlers.py", line 432, in decide_version
    pkg_list = self.protocol.get_ext_handler_pkgs(self.ext_handler)
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/common/protocol/wire.py", line 148, in get_ext_handler_pkgs
    man = self.client.get_ext_manifest(ext_handler, goal_state)
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/common/protocol/wire.py", line 809, in get_ext_manifest
    xml_text = self.fetch_manifest(ext_handler.versionUris)
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/common/protocol/wire.py", line 606, in fetch_manifest
    response = self.fetch(version.uri)
  File "bin/WALinuxAgent-2.2.18-py2.7.egg/azurelinuxagent/common/protocol/wire.py", line 653, in fetch
    return self.decode_config(resp.read())
  File "/usr/lib/python3.4/http/client.py", line 541, in read
    s = self._safe_read(self.length)
  File "/usr/lib/python3.4/http/client.py", line 691, in _safe_read
    chunk = self.fp.read(min(amt, MAXAMOUNT))
  File "/usr/lib/python3.4/socket.py", line 374, in readinto
    return self._sock.recv_into(b)
  File "/usr/lib/python3.4/ssl.py", line 769, in recv_into
    return self.read(nbytes, buffer)
  File "/usr/lib/python3.4/ssl.py", line 641, in read
    v = self._sslobj.read(len, buffer)
socket.timeout: The read operation timed out

2017/11/17 11:47:16.784583 WARNING Agent WALinuxAgent-2.2.18 launched with command 'python3 -u bin/WALinuxAgent-2.2.18-py2.7.egg -run-exthandlers' returned code: 1
2017/11/17 11:47:16.785549 WARNING Agent WALinuxAgent-2.2.18 is permanently blacklisted
```
This type of timeout should not be causing a blacklist.
