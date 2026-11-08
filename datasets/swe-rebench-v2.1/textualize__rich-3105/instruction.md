[BUG] `font-family` ignored in `html_export` due to user agent stylesheet for `<code>`
- [X] I've checked [docs](https://rich.readthedocs.io/en/latest/introduction.html) and [closed issues](https://github.com/Textualize/rich/issues?q=is%3Aissue+is%3Aclosed) for possible solutions.
- [X] I can't find my issue in the [FAQ](https://github.com/Textualize/rich/blob/master/FAQ.md).

**Describe the bug**

Run this code:

```py
import rich.console

try:
    test = 1
    raise Exception()
except Exception:
    console = rich.console.Console(record=True)
    console.print_exception(show_locals=True)
    html = console.export_html(inline_styles=True)
    with open("test.html", "w") as html_file:
        html_file.write(html)
```

You will get an `test.html` output file. Open it in Chrome.

I'm on macOS, and it shows up like this:

![image](https://github.com/Textualize/rich/assets/26592486/4b124132-b7a9-4156-bfd9-8912c65f2764)


Notice the lines are not aligned properly on the right side. Here is why:

![image](https://github.com/Textualize/rich/assets/26592486/8d6e13e6-2124-46e2-972d-1d4a31256615)

As you can see, Chrome's user agent stylesheet causes the `<code>` element to reset the `font-family` on the `<pre>` element back to `monospace`. [HIDDEN] and everything is fine:

![image](https://github.com/Textualize/rich/assets/26592486/ed1c2e6e-7d89-4d39-8301-cc92679458d9)

**Platform**
<details>
<summary>Click to expand</summary>

What platform (Win/Linux/Mac) are you running on? What terminal software are you using?
Mac with Chrome

```
❯ python -m rich.diagnose
╭───────────────────────── <class 'rich.console.Console'> ─────────────────────────╮
│ A high level console interface.                                                  │
│                                                                                  │
│ ╭──────────────────────────────────────────────────────────────────────────────╮ │
│ │ <console width=148 ColorSystem.TRUECOLOR>                                    │ │
│ ╰──────────────────────────────────────────────────────────────────────────────╯ │
│                                                                                  │
│     color_system = 'truecolor'                                                   │
│         encoding = 'utf-8'                                                       │
│             file = <_io.TextIOWrapper name='<stdout>' mode='w' encoding='utf-8'> │
│           height = 87                                                            │
│    is_alt_screen = False                                                         │
│ is_dumb_terminal = False                                                         │
│   is_interactive = True                                                          │
│       is_jupyter = False                                                         │
│      is_terminal = True                                                          │
│   legacy_windows = False                                                         │
│         no_color = False                                                         │
│          options = ConsoleOptions(                                               │
│                        size=ConsoleDimensions(width=148, height=87),             │
│                        legacy_windows=False,                                     │
│                        min_width=1,                                              │
│                        max_width=148,                                            │
│                        is_terminal=True,                                         │
│                        encoding='utf-8',                                         │
│                        max_height=87,                                            │
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
│             size = ConsoleDimensions(width=148, height=87)                       │
│        soft_wrap = False                                                         │
│           stderr = False                                                         │
│            style = None                                                          │
│         tab_size = 8                                                             │
│            width = 148                                                           │
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
│     'TERM_PROGRAM': 'vscode',      │
│     'COLUMNS': None,               │
│     'LINES': None,                 │
│     'JUPYTER_COLUMNS': None,       │
│     'JUPYTER_LINES': None,         │
│     'JPY_PARENT_PID': None,        │
│     'VSCODE_VERBOSE_LOGGING': None │
│ }                                  │
╰────────────────────────────────────╯
platform="Darwin"

❯ python -m pip freeze | grep rich
rich==13.4.2
```

</details>

### Additional contract requirements

- The `<code>` content in HTML exported by Rich must render with the same font family as its enclosing `<pre>` content, preventing browser default `<code>` styling from disrupting alignment. This applies to inline-style exports and HTML saved with `save_html`.
