Salmon commands don't return non-zero on error
For example:

```
$ salmon status; echo $?
Salmon not running.
0  # 0 is the exit for OK, but it's not OK!
```
