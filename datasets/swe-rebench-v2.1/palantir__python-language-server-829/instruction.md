Formatting hanging indents raises ValueError
Example file:

```python
def foo():
    print('asdf',
    file=None
    )
```

Formatting this raises:
```
Traceback (most recent call last):
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls_jsonrpc/endpoint.py", line 113, in consume
    self._handle_request(message['id'], message['method'], message.get('params'))
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls_jsonrpc/endpoint.py", line 182, in _handle_request
    handler_result = handler(params)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls_jsonrpc/dispatchers.py", line 23, in handler
    return method(**(params or {}))
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls/python_ls.py", line 347, in m_text_document__range_formatting
    return self.format_range(textDocument['uri'], range)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls/python_ls.py", line 258, in format_range
    return self._hook('pyls_format_range', doc_uri, range=range)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls/python_ls.py", line 155, in _hook
    return hook_handlers(config=self.config, workspace=workspace, document=doc, **kwargs)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/hooks.py", line 286, in __call__
    return self._hookexec(self, self.get_hookimpls(), kwargs)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/manager.py", line 93, in _hookexec
    return self._inner_hookexec(hook, methods, kwargs)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/manager.py", line 337, in traced_hookexec
    return outcome.get_result()
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/callers.py", line 80, in get_result
    raise ex[1].with_traceback(ex[2])
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/callers.py", line 52, in from_call
    result = func()
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/manager.py", line 335, in <lambda>
    outcome = _Result.from_call(lambda: oldcall(hook, hook_impls, kwargs))
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/manager.py", line 87, in <lambda>
    firstresult=hook.spec.opts.get("firstresult") if hook.spec else False,
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/callers.py", line 208, in _multicall
    return outcome.get_result()
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/callers.py", line 80, in get_result
    raise ex[1].with_traceback(ex[2])
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pluggy/callers.py", line 187, in _multicall
    res = hook_impl.function(*args)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls/plugins/autopep8_format.py", line 26, in pyls_format_range
    return _format(config, document, line_range=line_range)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/pyls/plugins/autopep8_format.py", line 34, in _format
    new_source = fix_code(document.source, options=options)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/autopep8.py", line 3414, in fix_code
    return fix_lines(sio.readlines(), options=options)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/autopep8.py", line 3489, in fix_lines
    fixed_source = fix.fix()
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/autopep8.py", line 600, in fix
    aggressive=self.options.aggressive))
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/autopep8.py", line 542, in _fix_source
    modified_lines = fix(result)
  File "/home/kb/apps/pls-venv/lib/python3.7/site-packages/autopep8.py", line 616, in _fix_reindent
    num_indent_spaces = int(result['info'].split()[1])
ValueError: invalid literal for int() with base 10: 'continuation'
```

Caused by palantir/python-language-server#719 replacing the autopep8 checker for `pycodestyle.continued_indentation`

### Additional contract requirements

- The source to format is:

```python
def foo():
    print('asdf',
    file=None
    )

bar = { 'foo': foo
}
```

- Formatting this source must not raise an error. Whether the whole document is formatted or a range covering the whole source is formatted, the result must be exactly one edit whose `newText` is:

```python
def foo():
    print('asdf',
          file=None
          )


bar = {'foo': foo
       }
```
