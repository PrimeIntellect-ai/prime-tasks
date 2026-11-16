force_to_top not respected by force_sort_within_sections
force_to_top seems to be applied before sections are sorted when force_sort_within_sections is specified:

testisort.py

```
import foo
import z
from foo import bar
```

~/.isort.cfg

```
[settings]
force_to_top=z
force_sort_within_sections=True
```

```
$ isort testisort.py
```

testisort.py

```
import foo
from foo import bar
import z
```

These seems like extremely counter-intuitive behavior.
