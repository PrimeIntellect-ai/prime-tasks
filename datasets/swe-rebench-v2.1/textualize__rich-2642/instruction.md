[BUG] export_html leaks style into the page
**Describe the bug**

Following discussion https://github.com/Textualize/rich/discussions/2640
Injecting HTML generated with Rich's `Console.export_html()` method seems to leak some style into the page.

![htmlstyleleak](https://user-images.githubusercontent.com/3999221/201484491-b8d6711a-92d7-4f08-baeb-473cdeaa9902.png)

The page is built with MkDocs + Material for MkDocs. The dark theme is activated.
The light theme is less impacted, I just see extra "bars" (like an empty code line) in-between block elements:

![lighttheme](https://user-images.githubusercontent.com/3999221/201484624-0b437e8e-bef5-405f-8329-ecb96d6da35b.png)

Code used to generate the HTML:

```python
import os

from rich.console import Console

report = """$ griffe check griffe -ssrc -b0.24.0 -a0.23.0
[bold]src/griffe/loader.py[/]:156: GriffeLoader.resolve_aliases([blue]only_exported[/]): [yellow]Parameter kind was changed[/]: positional or keyword -> keyword-only
etc.
"""

with open(os.devnull, "w") as devnull:
    console = Console(record=True, width=150, file=devnull)
    console.print(report, markup=True, highlight=False)
print(console.export_html(inline_styles=True))
```

Both `inline_styles=True` and `inline_styles=False` give the same result.

**Platform**
<details>
<summary>Click to expand</summary>

Linux

```console
$ python -m rich.diagnose
╭───────────────────────── <class 'rich.console.Console'> ─────────────────────────╮
│ A high level console interface.                                                  │
│                                                                                  │
│ ╭──────────────────────────────────────────────────────────────────────────────╮ │
│ │ <console width=239 ColorSystem.TRUECOLOR>                                    │ │
│ ╰──────────────────────────────────────────────────────────────────────────────╯ │
│                                                                                  │
│     color_system = 'truecolor'                                                   │
│         encoding = 'utf-8'                                                       │
│             file = <_io.TextIOWrapper name='<stdout>' mode='w' encoding='utf-8'> │
│           height = 58                                                            │
│    is_alt_screen = False                                                         │
│ is_dumb_terminal = False                                                         │
│   is_interactive = True                                                          │
│       is_jupyter = False                                                         │
│      is_terminal = True                                                          │
│   legacy_windows = False                                                         │
│         no_color = False                                                         │
│          options = ConsoleOptions(                                               │
│                        size=ConsoleDimensions(width=239, height=58),             │
│                        legacy_windows=False,                                     │
│                        min_width=1,                                              │
│                        max_width=239,                                            │
│                        is_terminal=True,                                         │
│                        encoding='utf-8',                                         │
│                        max_height=58,                                            │
│                        justify=None,                                             │
│                        overflow=None,                                            │
│                        no_wrap=False,                                            │
│                        highlight=None,                                           │
│                        markup=None,                                              │
│                        height=None                                               │
│                    )                                                             │
│            quiet = False                                                         │
│           record = False                                                         │
│         safe_box = True                                                          │
│             size = ConsoleDimensions(width=239, height=58)                       │
│        soft_wrap = False                                                         │
│           stderr = False                                                         │
│            style = None                                                          │
│         tab_size = 8                                                             │
│            width = 239                                                           │
╰──────────────────────────────────────────────────────────────────────────────────╯
╭─── <class 'rich._windows.WindowsConsoleFeatures'> ────╮
│ Windows features available.                           │
│                                                       │
│ ╭───────────────────────────────────────────────────╮ │
│ │ WindowsConsoleFeatures(vt=False, truecolor=False) │ │
│ ╰───────────────────────────────────────────────────╯ │
│                                                       │
│ truecolor = False                                     │
│        vt = False                                     │
╰───────────────────────────────────────────────────────╯
╭────── Environment Variables ───────╮
│ {                                  │
│     'TERM': 'xterm-256color',      │
│     'COLORTERM': 'truecolor',      │
│     'CLICOLOR': None,              │
│     'NO_COLOR': None,              │
│     'TERM_PROGRAM': None,          │
│     'COLUMNS': None,               │
│     'LINES': None,                 │
│     'JUPYTER_COLUMNS': None,       │
│     'JUPYTER_LINES': None,         │
│     'JPY_PARENT_PID': None,        │
│     'VSCODE_VERBOSE_LOGGING': None │
│ }                                  │
╰────────────────────────────────────╯
platform="Linux"
```

```console
% pdm list --freeze | grep rich
rich==12.6.0
```

</details>

### Additional contract requirements

- The HTML produced by `Console.export_html()` and `Console.save_html()` must wrap the rendered output in this exact structure, with the rendered output replacing `{code}`:

```html
    <pre style="font-family:Menlo,'DejaVu Sans Mono',consolas,'Courier New',monospace">
        <code>{code}</code>
    </pre>
```
