[BUG] repr fails for pd.Series in Jupyter with pretty.install()
**Describe the bug**

![image](https://user-images.githubusercontent.com/1360812/143245956-2ef17723-ddd0-487e-ad2a-11402ba58c1d.png)

Any pd.Series does not appear in Jupyter (both Lab and Notebook) after `pretty.install()`, but appears with `pretty.pprint()`.
This is not the case with other pandas structures.

**To Reproduce**

For copy paste purposes:

```python
from rich import pretty
pretty.install()

import pandas as pd
df = pd.DataFrame.from_records([{'a': 1, 'b': 1}, {'a': 2, 'b': 2}])
df.a  # no output

pretty.pprint(df.a)  # outputs fine
```

```
python -m rich.diagnose
python -m rich._windows
pip freeze | grep rich
```

```
╭─────────────────────── <class 'rich.console.Console'> ───────────────────────╮
│ A high level console interface.                                              │
│                                                                              │
│ ╭──────────────────────────────────────────────────────────────────────────╮ │
│ │ <console width=80 ColorSystem.TRUECOLOR>                                 │ │
│ ╰──────────────────────────────────────────────────────────────────────────╯ │
│                                                                              │
│     color_system = 'truecolor'                                               │
│         encoding = 'utf-8'                                                   │
│             file = <_io.TextIOWrapper name='<stdout>' mode='w'               │
│                    encoding='utf-8'>                                         │
│           height = 24                                                        │
│    is_alt_screen = False                                                     │
│ is_dumb_terminal = False                                                     │
│   is_interactive = True                                                      │
│       is_jupyter = False                                                     │
│      is_terminal = True                                                      │
│   legacy_windows = False                                                     │
│         no_color = False                                                     │
│          options = ConsoleOptions(                                           │
│                        size=ConsoleDimensions(width=80, height=24),          │
│                        legacy_windows=False,                                 │
│                        min_width=1,                                          │
│                        max_width=80,                                         │
│                        is_terminal=True,                                     │
│                        encoding='utf-8',                                     │
│                        max_height=24,                                        │
│                        justify=None,                                         │
│                        overflow=None,                                        │
│                        no_wrap=False,                                        │
│                        highlight=None,                                       │
│                        markup=None,                                          │
│                        height=None                                           │
│                    )                                                         │
│            quiet = False                                                     │
│           record = False                                                     │
│         safe_box = True                                                      │
│             size = ConsoleDimensions(width=80, height=24)                    │
│        soft_wrap = False                                                     │
│           stderr = False                                                     │
│            style = None                                                      │
│         tab_size = 8                                                         │
│            width = 80                                                        │
╰──────────────────────────────────────────────────────────────────────────────╯
platform="Linux"
WindowsConsoleFeatures(vt=False, truecolor=False)
rich==10.14.0
```

### Additional contract requirements

- Add a public function `_ipy_display_hook(value, console=None, overflow="ignore", crop=False, indent_guides=False, max_length=None, max_string=None, expand_all=False)` in the module `rich.pretty`. It returns `None`.
- The function produces no output and returns `None` when the value is `None` or a Rich-generated Jupyter renderable.
- In a Jupyter console, allow IPython to render a value when one of its supported representations produces a value. Treat a supported representation that raises an exception as unavailable and consider the remaining supported representations. Use Rich output if none of the supported representations produces a value.
- Otherwise the value is printed using Rich's `Pretty` renderer. A console renderable that needs a leading newline is rendered with one.
- Outside Jupyter, values with supported IPython representation methods are still displayed through Rich.
