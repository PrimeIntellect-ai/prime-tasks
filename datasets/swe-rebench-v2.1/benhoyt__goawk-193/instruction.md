Exit status code in BEGIN should apply if END has exit
If there's an `exit` in the `BEGIN` block with an exit code, that status code should be returned, even if there's an `exit` in the `END` block with a zero exit code. For example:

```
$ goawk 'BEGIN { exit 23 }; END { exit }'; echo $?
0
```

All other AWKs print 23.

Thanks @raygard for the bug report.
