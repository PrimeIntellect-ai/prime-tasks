fs/_ftp_parse.py fails when parsing directory listing on NT format if folder or filename contains AM or PM
[HIDDEN]

Example file listing that fails:
```
01-29-20  04:11AM       <DIR>          Clock at AM or PM
```
This fails with the following trace
```
  File ".venv\lib\site-packages\fs\ftpfs.py", line 746, in scandir
    if not self.supports_mlst and not self.getinfo(path).is_dir:
  File ".venv\lib\site-packages\fs\ftpfs.py", line 614, in getinfo
    directory = self._read_dir(dir_name)
  File ".venv\lib\site-packages\fs\ftpfs.py", line 495, in _read_dir
    _list = [Info(raw_info) for raw_info in ftp_parse.parse(lines)]
  File ".venv\lib\site-packages\fs\_ftp_parse.py", line 70, in parse
    raw_info = parse_line(line)
  File ".venv\lib\site-packages\fs\_ftp_parse.py", line 81, in parse_line
    return decode_callable(line, match)
  File ".venv\lib\site-packages\fs\_ftp_parse.py", line 163, in decode_windowsnt
    raw_info["details"]["size"] = int(match.group("size"))
ValueError: invalid literal for int() with base 10: ''
```

### Additional contract requirements

- NT-format directory listings must parse entries whose file or folder names contain `AM` or `PM`. Those tokens must be treated as part of the name, not the modified timestamp, and the parsed entry must retain its correct name and metadata.
