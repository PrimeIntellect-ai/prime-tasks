Exception on run with cyrillic symbols in the hostname
Sighted it on the Windows 7 system with python 3.6.3 and waitress 1.1.0
```
File "c:\users\user\appdata\local\programs\python\python36\lib\site-packages\waitress\__init__.py", line 11, in serve
server = _server(app, **kw)
File "c:\users\user\appdata\local\programs\python\python36\lib\site-packages\waitress\server.py", line 85, in create_server
sockinfo=sockinfo)
File "c:\users\user\appdata\local\programs\python\python36\lib\site-packages\waitress\server.py", line 184, in __init__
self.server_name = self.get_server_name(self.effective_host)
File "c:\users\user\appdata\local\programs\python\python36\lib\site-packages\waitress\server.py", line 206, in get_server_name

server_name = self.socketmod.gethostbyaddr(server_name)[0]
UnicodeDecodeError: 'utf-8' codec can't decode byte 0xd6 in position 6: unexpected end of data
```

### Additional contract requirements

Server startup must tolerate a `UnicodeDecodeError` raised during hostname lookup for hostnames containing Cyrillic symbols.
