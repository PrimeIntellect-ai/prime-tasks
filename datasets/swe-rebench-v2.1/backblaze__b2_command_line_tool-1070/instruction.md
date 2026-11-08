Attempting to generate an authorized URL using b2id fails
Running

`b2 file url --with-auth --duration 604800 b2id://[REDACTED]`

Results in a stack trace - Works just fine without specifying --with-auth.
```
Traceback (most recent call last):
  File "<frozen runpy>", line 198, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "C:\Users\[REDACTED]\.pyenv\pyenv-win\versions\3.13.1\Scripts\b2.exe\__main__.py", line 4, in <module>
    from b2._internal.b2v4.__main__ import main
  File "C:\Users\[REDACTED]\.pyenv\pyenv-win\versions\3.13.1\Lib\site-packages\b2\_internal\b2v4\__main__.py", line 13, in <module>
    main()
    ~~~~^^
  File "C:\Users\[REDACTED]\.pyenv\pyenv-win\versions\3.13.1\Lib\site-packages\b2\_internal\console_tool.py", line 5583, in main
    exit_status = ct.run_command(sys.argv)
  File "C:\Users\[REDACTED]\.pyenv\pyenv-win\versions\3.13.1\Lib\site-packages\b2\_internal\console_tool.py", line 5456, in run_command
    return command.run(args)
           ~~~~~~~~~~~^^^^^^
  File "C:\Users\[REDACTED]\.pyenv\pyenv-win\versions\3.13.1\Lib\site-packages\b2\_internal\console_tool.py", line 1082, in run
    return self._run(args)
           ~~~~~~~~~^^^^^^
  File "C:\Users\[REDACTED]\.pyenv\pyenv-win\versions\3.13.1\Lib\site-packages\b2\_internal\console_tool.py", line 2903, in _run
    [HIDDEN]
```

### Additional contract requirements

- When `--with-auth` is used with a `b2id://` URL, the command must write exactly `ERROR: --with-auth param cannot be used with `b2id://` urls. Please, use `b2://bucket/filename` url format instead\n` to stderr.
