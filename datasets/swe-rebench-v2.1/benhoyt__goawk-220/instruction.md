Allow line break between `}` and `while`
See:
```
$ goawk 'BEGIN{do{}
while(0)}'
<cmdline>:1:11: expected while instead of <newline>
BEGIN{do{}
          ^
$
```
POSIX allows line breaks after every closing brace, the one terminating a `do` group is no exception.
