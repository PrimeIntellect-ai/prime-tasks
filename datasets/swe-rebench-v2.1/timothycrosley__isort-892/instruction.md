Add support for PyCharm style alphabetic sorting (edited from: all upper cases name is sorted top most)
Below is the sorted result using my isort configuration, you could see the both 'BALL' and `RC` is placed at the top most. The name `Action` is placed below 'BALL' and 'RC' is not correct for me:

```python
from pkg import BALL
from pkg import RC
from pkg import Action
from pkg import Bacoo
from pkg import RCNewCode
from pkg import actual
from pkg import rc
from pkg import recorder
```

What I expected is:
```python
from pkg import Action
from pkg import BALL
from pkg import Bacoo
from pkg import RC
from pkg import RCNewCode
from pkg import actual
from pkg import rc
from pkg import recorder
```

That means following the default python string odering:
```python
>>> 'BALL' < 'RC' < 'Action'
False
>>> 'Action' < 'BALL' < 'RC'
True
```

So I wonder whether there is any configuration can make it?


Below is my isort configuration:
```ini
[isort]
line_length = 80
indent = '  '
force_single_line = True
known_first_party=test
```

### Additional contract requirements

Provide a user-configurable way to select case-sensitive Python string ordering when PyCharm-style sorting is desired. The option is exposed as the `--case-sensitive` command-line flag; when it is not given, module names keep the default case-insensitive ordering.
