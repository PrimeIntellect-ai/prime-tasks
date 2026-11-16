Bug: Incorrect git config parsing (error when cloning local repository with trailing backslash on Windows)
I ran into a ValueError ("escape character followed by unknown character 102...") when trying to clone a local repository on Windows. The issue turned out to be because of how trailing backslashes interact with how dulwich parses git config files.

**Reproduction steps**

(I think this affects lots of other operations on things that have been cloned from a local remote on Windows, but I'll show a way to reproduce by cloning, which was how I first encountered the issue.)

Environment: Windows 10, with output of `pip list` being
```
Package    Version
---------- ---------
certifi    2022.9.24
dulwich    0.20.50
pip        21.1.1
setuptools 56.0.0
urllib3    1.26.12
```

1. Create a new git repository that we're going to clone. In Powershell:

```
mkdir C:\source_repo
cd C:\source_repo
git init
git commit --allow-empty -m "Initial commit"
```

2. Try to clone it using dulwich:

```
python -c "from dulwich import porcelain; porcelain.clone('C:\\source_repo\\', 'C:\\cloned_repo')"
```

(note the trailing backslash in the path for `source_repo` -- without it it works fine).

**Expected result**

The `dulwich.porcelain.clone` command works and clones the repository.

**Actual result**

We get an exception:

```
Traceback (most recent call last):
  File "C:\Users\hliu\venvs\test_dulwich\lib\site-packages\dulwich\config.py", line 413, in _parse_string
    v = _ESCAPE_TABLE[value[i]]
KeyError: 102

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\porcelain.py", line 551, in clone
    return client.clone(
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\client.py", line 761, in clone
    _import_remote_refs(
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\refs.py", line 1211, in _import_remote_refs
    refs_container.import_refs(
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\refs.py", line 187, in import_refs
    self.set_if_equals(
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\refs.py", line 871, in set_if_equals
    self._log(
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\refs.py", line 128, in _log
    self._logger(ref, old_sha, new_sha, committer, timestamp, timezone, message)
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\repo.py", line 1207, in _write_reflog
    config = self.get_config_stack()
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\repo.py", line 713, in get_config_stack
    backends = [self.get_config()] + StackedConfig.default_backends()
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\repo.py", line 1602, in get_config
    return ConfigFile.from_path(path)
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\config.py", line 593, in from_path
    ret = cls.from_file(f)
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\config.py", line 583, in from_file
    value = _parse_string(continuation)
  File "C:\Users\<username>\venvs\test_dulwich\lib\site-packages\dulwich\config.py", line 419, in _parse_string
    raise ValueError(
ValueError: escape character followed by unknown character 102 at 16 in bytearray(b'C:\\\\source_repo\\fetch = +refs/heads/*:refs/remotes/origin/*')
```

**Analysis**

I believe this is a result of incorrect parsing of the git config file by dulwich.

When you clone the repository like this, the contents of `C:\cloned_repo\.git\config` will contain a section like:

```
[remote "origin"]
	url = C:\\source_repo\\
	fetch = +refs/heads/*:refs/remotes/origin/*
```

dulwich (incorrectly) treats the final backslash in `url = C:\\source_repo\\` as a line continuation character, so joins the two lines, and then gives an error when trying to parse `url = C:\\source_repo\\fetch ...`

The code to do this is [here](https://github.com/jelmer/dulwich/blob/master/dulwich/config.py#L567-L580), where we simply treat every line ending in backslash as continuing onto the next line. This is incorrect in when the actual value on the line ends in an escape sequence `\\`.

Compare to how the git code parses config files [here](https://github.com/git/git/blob/c03801e19cb8ab36e9c0d17ff3d5e0c3b0f24193/config.c#L848-L849), [HIDDEN]

### Additional contract requirements

- A config value that ends in an escaped backslash (`\\`) keeps one literal backslash at its end, and the setting on the next line is read as its own setting.
- A line that ends in an unescaped backslash continues the value onto the next line.
- Cloning a local repository whose path ends in a backslash succeeds, and the clone's `origin` remote points at that path.
