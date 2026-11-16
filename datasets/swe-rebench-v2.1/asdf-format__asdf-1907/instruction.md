`asdf.util.load_yaml` fails on recursive object
# Description of the problem

Attempting to read an asdf file with a recursive reference using `asdf.util.load_yaml` fails with `ConstructorError: found unconstructable recursive node`.

# Example of the problem

```python
import asdf
d = {}
d['a'] = d
asdf.AsdfFile(d).write_to("recursive.asdf")
asdf.util.load_yaml("recursive.asdf")
```
Produces:
```
ConstructorError: found unconstructable recursive node
```

Note that passing `tagged=True` is a work-around for the above issue (as it triggers using the `AsdfLoader` which handles the recursion).

# System information

asdf version: main
python version: 3.10
operating system: osx
