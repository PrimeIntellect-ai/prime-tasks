`ui.codemirror` does not apply changes with special characters like 🔄
### First Check

- [x] I added a very descriptive title here.
- [x] This is not a Q&A. I am sure something is wrong with NiceGUI or its documentation.
- [x] I used the GitHub search to find a similar [issue](https://github.com/zauberzeug/nicegui/issues) and came up empty.

### Example Code

```python
go and see: https://github.com/gbrault/ngcmbug
```

### Description

- start the app in vs-code with justmycode=false
- open a browser http://127.0.0.1:8081
- add a char on the first line

triggers

```
Cannot apply change set to a document with the wrong length
Traceback (most recent call last):
  File "d:\SeaDev\ngcmbug\env\Lib\site-packages\nicegui\events.py", line 436, in handle_event
    result = cast(Callable[[EventT], Any], handler)(arguments)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "d:\SeaDev\ngcmbug\env\Lib\site-packages\nicegui\elements\mixins\value_element.py", line 40, in handle_change
    self.set_value(self._event_args_to_value(e))
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "d:\SeaDev\ngcmbug\env\Lib\site-packages\nicegui\elements\codemirror.py", line 335, in _event_args_to_value
    new_value = changeset.apply(self.value)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "d:\SeaDev\ngcmbug\env\Lib\site-packages\nicegui\elements\codemirror.py", line 363, in apply
    raise ValueError('Cannot apply change set to a document with the wrong length')
ValueError: Cannot apply change set to a document with the wrong length
```


### NiceGUI Version

2.13.0

### Python Version

3.12

### Browser

Chrome

### Operating System

Windows

### Additional Context

_No response_
