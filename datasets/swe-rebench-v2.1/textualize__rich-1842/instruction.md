[BUG] rich.inspect on a module: AttributeError: Unknown C global variable '__class__'
**Describe the bug**

Trying to use `rich.inspect` on the module [Faiss](https://github.com/facebookresearch/faiss), (built by [these guys](https://github.com/kyamagu/faiss-wheels)) raises an `AttributeError` exception.

repro:

```shell
pip install --user faiss-cpu rich
python -c 'import rich, faiss; rich.inspect(faiss)'
```
output:

<details>
<summary>Click to expand</summary>

```python
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/__init__.py", line 168, in inspect
    _console.print(_inspect)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/console.py", line 1621, in print
    extend(render(renderable, render_options))
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/console.py", line 1259, in render
    for render_output in iter_render:
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/panel.py", line 160, in __rich_console__
    else console.measure(
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/console.py", line 1212, in measure
    measurement = Measurement.get(self, options or self.options, renderable)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 107, in get
    get_console_width(console, options)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/padding.py", line 132, in __rich_measure__
    measure_min, measure_max = Measurement.get(console, options, self.renderable)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 107, in get
    get_console_width(console, options)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/console.py", line 468, in __rich_measure__
    return measure_renderables(console, options, self.renderables)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 142, in measure_renderables
    measurements = [
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 143, in <listcomp>
    get_measurement(console, options, renderable) for renderable in renderables
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 107, in get
    get_console_width(console, options)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/table.py", line 296, in __rich_measure__
    self._calculate_column_widths(
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/table.py", line 482, in _calculate_column_widths
    width_ranges = [
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/table.py", line 483, in <listcomp>
    self._measure_column(console, options, column) for column in columns
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/table.py", line 678, in _measure_column
    _min, _max = get_render_width(console, options, cell.renderable)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 107, in get
    get_console_width(console, options)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/padding.py", line 132, in __rich_measure__
    measure_min, measure_max = Measurement.get(console, options, self.renderable)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/measure.py", line 107, in get
    get_console_width(console, options)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/pretty.py", line 270, in __rich_measure__
    pretty_str = pretty_repr(
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/pretty.py", line 753, in pretty_repr
    node = traverse(_object, max_length=max_length, max_string=max_string)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/pretty.py", line 721, in traverse
    node = _traverse(_object, root=True)
  File "/home/pbsds/.cache/pypoetry/virtualenvs/foobar-u94_3CgC-py3.9/lib/python3.9/site-packages/rich/pretty.py", line 665, in _traverse
    [HIDDEN]
  File "/usr/lib/python3.9/abc.py", line 119, in __instancecheck__
    return _abc_instancecheck(cls, instance)
AttributeError: Unknown C global variable '__class__'
```
</details>

**Platform**
<details>
<summary>Click to expand</summary>

Linux - Manjaro GNOME, using lxterminal

```
╭───────────────────────── <class 'rich.console.Console'> ─────────────────────────╮
│ A high level console interface.                                                  │
│                                                                                  │
│ ╭──────────────────────────────────────────────────────────────────────────────╮ │
│ │ <console width=115 ColorSystem.TRUECOLOR>                                    │ │
│ ╰──────────────────────────────────────────────────────────────────────────────╯ │
│                                                                                  │
│     color_system = 'truecolor'                                                   │
│         encoding = 'utf-8'                                                       │
│             file = <_io.TextIOWrapper name='<stdout>' mode='w' encoding='utf-8'> │
│           height = 56                                                            │
│    is_alt_screen = False                                                         │
│ is_dumb_terminal = False                                                         │
│   is_interactive = True                                                          │
│       is_jupyter = False                                                         │
│      is_terminal = True                                                          │
│   legacy_windows = False                                                         │
│         no_color = False                                                         │
│          options = ConsoleOptions(                                               │
│                        size=ConsoleDimensions(width=115, height=56),             │
│                        legacy_windows=False,                                     │
│                        min_width=1,                                              │
│                        max_width=115,                                            │
│                        is_terminal=True,                                         │
│                        encoding='utf-8',                                         │
│                        max_height=56,                                            │
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
│             size = ConsoleDimensions(width=115, height=56)                       │
│        soft_wrap = False                                                         │
│           stderr = False                                                         │
│            style = None                                                          │
│         tab_size = 8                                                             │
│            width = 115                                                           │
╰──────────────────────────────────────────────────────────────────────────────────╯
platform="Linux"
WindowsConsoleFeatures(vt=False, truecolor=False)
rich @ file:///home/pbsds/.cache/pypoetry/artifacts/1e/d2/56/58ed32503426d13d7f2181d73a291742842d3876c387b1f4ac2e3d2807/rich-10.16.2-py3-none-any.whl
```
</details>

### Additional contract requirements

- `rich.inspect` must not propagate an `AttributeError` when inspecting a target whose `__class__` lookup fails, including the reported Faiss module.
