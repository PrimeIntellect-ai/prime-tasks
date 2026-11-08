`indent_style = space` is ignored if `indent_size = unset`
If the `indent_size` is not set for a file, the check for `indent_style = space` is silently skipped.

Example:
```ini
# .editorconfig
root = true
[*]
indent_style = space
# indent_size = 3
```
```
# example.txt (whitespace made visible)
this line is unindented -- should PASS
····this line is indented with 4 spaces -- should PASS
￫       this line is indented with 1 tab -- should FAIL
￫       ····this line is indented with 1 tab and 4 spaces -- should FAIL
```
```console
$ ec example.txt  # Should fail on the latter 2 lines
$ echo $?
0
```

Note that if the `indent_size = 3` is uncommented from the `.editorconfig` but we disable the indentation size check, the expected errors are reported:
```console
$ ec -disable-indent-size example.txt
example.txt:
	3: Wrong indent style found (tabs instead of spaces)
	4: Wrong indent style found (tabs instead of spaces)

2 errors found
```
