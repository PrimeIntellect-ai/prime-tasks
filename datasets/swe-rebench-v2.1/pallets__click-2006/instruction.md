Regression in click>=8; click.Path says file doesn't exist when it does
<!--
This issue tracker is a tool to address bugs in Click itself. Please use
Pallets Discord or Stack Overflow for questions about your own code.

Replace this comment with a clear outline of what the bug is.
-->

https://github.com/pallets/click/pull/1825 seems to introduce a regression. A script which worked with `click<8` does not work when upgraded to `click>=8`, and the call to `os.readlink` this PR introduces seems to be the cause. I.e. it looks like fixing symlinks in this case for old Pythons on Windows has broken symlinks for more current Pythons on Linux, however I have not tested as thoroughly as I should be making that claims like that!

I have a kubernetes "secret" (could just as easily be a configmap) and these create multiple symlinks do enable atomic replacement of all files in a secret or config map at once. An example secret might look like this:

```
# ls -lart
total 0
lrwxrwxrwx    1 root     root            14 May 20 14:12 mysecret -> ..data/mysecret
lrwxrwxrwx    1 root     root            31 May 20 14:12 ..data -> ..2021_05_20_14_12_50.273872148
drwxr-xr-x    2 root     root           100 May 20 14:12 ..2021_05_20_14_12_50.273872148
drwxrwxrwt    3 root     root           140 May 20 14:12 .
drwxr-xr-x    1 root     root            50 May 20 14:12 ..
```

(Yes, those files and folders have a `..` prefix which is confusing, and no I can't make kubernetes not do that).

Lets say this secret was mounted as `/foo`. Prior to https://github.com/pallets/click/pull/1825, the code would call `os.path.realpath` on `/foo/mysecret` it would resolve the symlink correctly and end up with `/foo/..2021_05_20_14_12_50.273872148/mysecret`

After https://github.com/pallets/click/pull/1825, it calls `os.readlink` and gets `..data/mysecret` (not an abspath). When you call `os.path.realpath` on that it prefixes the current directory, so if you are in `/` you get `/..data/tls.crt`. `os.stat` on `/..data/mysecret` fails. But `os.stat` on `/foo/mysecret` does not. So definitely a regression, and I think a wrong behaviour.

I think calling `os.readlink` is not a replacement for a proper symlink resolver. Given click only supports Python 3.6 or later, I wonder if using `pathlib.Path(...).resolve()` here would be a better option. It does have a Windows symlink resolver (https://github.com/python/cpython/blob/3.6/Lib/pathlib.py#L181) and a Posix one (https://github.com/python/cpython/blob/3.6/Lib/pathlib.py#L303). Though I don't have a Windows machine to test it out.

<!--
Describe how to replicate the bug.

Include a minimal reproducible example that demonstrates the bug.
Include the full traceback if there was an exception.
-->

For a reproducer I took the example for `click.Path` from the docs and enabled the resolve_path and exists checks:

```
import click

@click.command()
@click.argument('filename', type=click.Path(exists=True, resolve_path=True))
def touch(filename):
    """Print FILENAME if the file exists."""
    click.echo(click.format_filename(filename))


if __name__ == '__main__':
    touch()
```

Then I made an empty file with a symlink pointing to it:

```
# mkdir tst
# cd tst
# touch foo
# ln -s foo bar
# ls
-rw-r--r--    1 root     root             0 May 20 15:10 foo
lrwxrwxrwx    1 root     root             3 May 20 15:10 bar -> foo
```

```
/ # /app/bin/python /app/test.py /tst/bar
Usage: test.py [OPTIONS] FILENAME
Try 'test.py --help' for help.

Error: Invalid value for 'FILENAME': Path '/tst/bar' does not exist.
```

However if I downgrade click:

```
/ # /app/bin/pip install 'click<8'
Collecting click<8
  Using cached click-7.1.2-py2.py3-none-any.whl (82 kB)
Installing collected packages: click
  Attempting uninstall: click
    Found existing installation: click 8.0.1
    Uninstalling click-8.0.1:
      Successfully uninstalled click-8.0.1
Successfully installed click-7.1.2
```

```
/ # /app/bin/python /app/test.py /tst/bar
/tst/foo
```

Because i'm paranoid, i upgraded click again and confirmed the reproducer fails again. It does.

<!--
Describe the expected behavior that should have happened but didn't.
-->

Environment:

- Linux (Alpine)
- Python version: 3.8.10
- Click version: >8

PS, transcript from running the reproducer on macOS Catalina too, with python 3.9 from brew:

```
% mkdir click-bug
% cd click-bug
% python3 -m venv venv
% source venv/bin/activate
(venv) % pip install click
Collecting click
  Downloading click-8.0.1-py3-none-any.whl (97 kB)
     |████████████████████████████████| 97 kB 5.7 MB/s
Installing collected packages: click
Successfully installed click-8.0.1
(venv)  % mkdir tst
(venv)  % cd tst
(venv)  % touch foo
(venv)  % ln -s foo bar
(venv)  % cd ..
(venv)  % vi test.py
(venv)  % python test.py tst/bar
Usage: test.py [OPTIONS] FILENAME
Try 'test.py --help' for help.

Error: Invalid value for 'FILENAME': Path 'tst/bar' does not exist.
(venv) % pip install "click<8"
Collecting click<8
  Downloading click-7.1.2-py2.py3-none-any.whl (82 kB)
     |████████████████████████████████| 82 kB 3.0 MB/s
Installing collected packages: click
  Attempting uninstall: click
    Found existing installation: click 8.0.1
    Uninstalling click-8.0.1:
      Successfully uninstalled click-8.0.1
Successfully installed click-7.1.2
(venv) % python test.py tst/bar
/Users/me/click-bug/tst/foo
```

### Additional contract requirements

- `click.Path(resolve_path=True)` must return the resolved filesystem path as a
  string, so that a relative symlink target is resolved relative to the
  directory containing the symlink.
- `click.Path(exists=True, resolve_path=True)` must accept a path that is a
  symlink to an existing file (it must not raise `click.BadParameter`), and the
  existence check must be performed against the resolved path.
- For the Kubernetes-style chain (`mysecret -> ..data/mysecret`,
  `..data -> ..<version>`), converting `mysecret` with
  `exists=True, resolve_path=True` must succeed and the returned path must refer
  to the same file as the versioned target.
