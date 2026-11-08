Fails when project root is a symlink
**Describe the bug**

When any element in the project root path is a symlink, formatting fails.

**To Reproduce**

Steps to reproduce the behavior:

```
$ # On macOS, $TMPDIR begins with a symlink:

$ echo $TMPDIR
/var/folders/z5/fclwwdms3r1gq4k4p3pkvvc00000gn/T/

$ readlink /var
private/var

$ cd "$(mktemp -d)"

$ cat .treefmt.toml
[formatter.echo]
command = "echo"
includes = ["*.txt"]

$ touch puppy.txt

$ treefmt puppy.txt
Error: path puppy.txt not inside the tree root /var/folders/z5/fclwwdms3r1gq4k4p3pkvvc00000gn/T/tmp.OmlZjRNdbX
```

**Expected behavior**

The symlink is followed and files are formatted correctly.

**System information**

macOS Sequoia 15.4.1 (24E263), M4 Max (aarch64-darwin)

```
$ treefmt --version
treefmt v2.2.1
```

**Additional context**

Possibly related:
- #528
- #508
- #221
