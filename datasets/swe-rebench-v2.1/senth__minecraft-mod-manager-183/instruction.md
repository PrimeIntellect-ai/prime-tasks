`update --pretend` throws errors
### Describe the bug
When there are updates and you run `--pretend` it gets the version from the file. But since there's no file to read it can't get the updated version.

### Steps to reproduce
Steps to reproduce the behavior:
1. Ran `mcman install -v 1.16.5 carpet`
2. Then ran `mcman update --pretend`

### Expected Behavior
Should display the updated version and not throw an error

### Possible solution
[HIDDEN]

### Info
 - OS: Ubuntu
 - Python --version: 3.8.6
 - minecraft-mod-manager --version: 1.2.4


## From #179
### Describe the bug
Tried updating all mods and it showed errors on several mods

```
Failed to parse mod file mods\CraftTweaker-fabric-1.18.2-9.1.127.jar
Traceback (most recent call last):
  File "C:\Users\redacted\AppData\Roaming\Python\Python310\site-packages\minecraft_mod_manager\gateways\jar_parser.py", line 50, in _get_mod_info
    with ZipFile(file, "r") as zip:
  File "C:\Users\redacted\AppData\Local\Programs\Python\Python310\lib\zipfile.py", line 1240, in __init__
    self.fp = io.open(file, filemode)
FileNotFoundError: [Errno 2] No such file or directory: 'mods\\CraftTweaker-fabric-1.18.2-9.1.127.jar'

!!! Please report this and paste the above message !!!
    ❌ Corrupted file.
```

### Steps to reproduce
Steps to reproduce the behavior:
1. Ran `minecraft-mod-manager.exe --pretend -d mods -v 1.18.2 --mod-loader=fabric update`

### Expected Behavior
Will show mods to be updated

### Info
 - OS: win10
 - Python --version: 3.10
 - minecraft-mod-manager --version: 1.27

### Additional contract requirements

- When an update is available in pretend mode, the preview must identify the version the mod would receive.
- Pretend mode must still preview an update when the installed mod file is missing; it must not require reading that local file.
