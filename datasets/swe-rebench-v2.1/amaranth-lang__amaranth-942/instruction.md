`amaranth.lib.enum` does not support functional syntax
Functional syntax defined [here](https://docs.python.org/3/library/enum.html):

```python
# functional syntax
Color = Enum('Color', ['RED', 'GREEN', 'BLUE'])
```

MCVE:

```python
import enum as pyenum
import amaranth.lib.enum
pyenum.Enum("FOO", ["BAR", "BAZ"])
enum.Enum("FOO", ["BAR", "BAZ"])
```

Results:

```
TypeError                                 Traceback (most recent call last)
Cell In[44], line 4
      2 import amaranth.lib.enum
      3 pyenum.Enum("FOO", ["BAR", "BAZ"])
----> 4 enum.Enum("FOO", ["BAR", "BAZ"])

TypeError: EnumMeta.__call__() takes 2 positional arguments but 3 were given
```
