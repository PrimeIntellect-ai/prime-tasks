Case sensitivity inconsistency between --map-syntax and --language command line parameters

**What steps will reproduce the bug?**

1. create a valid todo.txt file http://todotxt.org/ with a custom name, e.g. todo_2025-01.txt
2. run `bat --map-syntax "todo*.txt:todo.txt" todo_2025-01.txt`
3. run `bat --map-syntax "todo*.txt:Todo.txt" todo_2025-01.txt`
4. run `bat --language todo.txt todo_2024-12.txt`

**What happens?**

number 2 will fail with:

    [bat error]: unknown syntax: 'todo.txt'

**What did you expect to happen instead?**

I expected syntax highlighting in the same way that the language flag works.
  * It appears that the language flag is __case insensitive__.
 * It appears that the map-syntax flag is **case sensitive**.

**How did you install `bat`?**

download [msvc zip](https://github.com/sharkdp/bat/releases/download/v0.25.0/bat-v0.25.0-x86_64-pc-windows-msvc.zip) from https://github.com/sharkdp/bat/releases/tag/v0.25.0 extract exe to path.

---

**bat version and environment**

    C:\>bat --version
    bat 0.25.0 (25f4f96)

`C:\>bat  --diagnostic`

#### Software version

bat 0.25.0 (25f4f96)

#### Operating system

Windows 6.2.9200

#### Command-line

```bash
bat --diagnostic
```

#### Environment variables

```bash
BAT_CACHE_PATH=<not set>
BAT_CONFIG_PATH=<not set>
BAT_OPTS=<not set>
BAT_PAGER=<not set>
BAT_PAGING=<not set>
BAT_STYLE=<not set>
BAT_TABS=<not set>
BAT_THEME=<not set>
COLORTERM=<not set>
LANG=<not set>
LC_ALL=<not set>
LESS=<not set>
MANPAGER=<not set>
NO_COLOR=<not set>
PAGER=<not set>
SHELL=<not set>
TERM=<not set>
XDG_CACHE_HOME=<not set>
XDG_CONFIG_HOME=<not set>
```

#### System Config file

Could not read contents of 'C:\ProgramData\bat\config': The system cannot find the path specified. (os error 3).

#### Config file

Could not read contents of 'C:\Users\clach04\AppData\Roaming\bat\config': The system cannot find the path specified. (os error 3).

#### Custom assets metadata

Could not read contents of 'C:\Users\clach04\AppData\Local\bat\metadata.yaml': The system cannot find the path specified. (os error 3).

#### Custom assets

'C:\Users\clach04\AppData\Local\bat' not found

#### Compile time information

- Profile: release
- Target triple: x86_64-pc-windows-msvc
- Family: windows
- OS: windows
- Architecture: x86_64
- Pointer width: 64
- Endian: little
- CPU features: cmpxchg16b,fxsr,sse,sse2,sse3
- Host: x86_64-pc-windows-msvc
