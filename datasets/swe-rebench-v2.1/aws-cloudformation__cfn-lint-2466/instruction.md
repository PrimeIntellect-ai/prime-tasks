Cannot list all the rules
### CloudFormation Lint Version

0.70.0

### What operating system are you using?

Windows

### Describe the bug

`cfn-lint --list-rules` throws below Error.(username is masked.)

```
Traceback (most recent call last):
  File "C:\Users\${username}\AppData\Local\Programs\Python\Python39\lib\runpy.py", line 197, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "C:\Users\${username}\AppData\Local\Programs\Python\Python39\lib\runpy.py", line 87, in _run_code
    exec(code, run_globals)
  File "C:\Users\${username}\AppData\Local\Programs\Python\Python39\Scripts\cfn-lint.exe\__main__.py", line 7, in <module>
  File "C:\Users\${username}\AppData\Local\Programs\Python\Python39\lib\site-packages\cfnlint\__main__.py", line 38, in main
    (args, filenames, formatter) = cfnlint.core.get_args_filenames(sys.argv[1:])
  File "C:\Users\${username}\AppData\Local\Programs\Python\Python39\lib\site-packages\cfnlint\core.py", line 235, in get_args_filenames
    print(rules)
  [HIDDEN]
  [HIDDEN]
AttributeError: 'str' object has no attribute 'id'
```


### Expected behavior

show list all the rules.

### Reproduction template

This is not bug of linting.

### Additional contract requirements

- The `cfn-lint --list-rules` command must complete successfully and display all registered rules.
