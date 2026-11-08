Wrong order of output with pipe and print
Hi!

```awk
# delme.awk
BEGIN {
  print "222" | (cmd = "cat")
  close(cmd)
  print "DONE"
}
```

```
$ gawk -f delme.awk
222
DONE

$ mawk -f delme.awk
222
DONE

$ ./soft/bwk -f delme.awk
222
DONE

$ ./soft/goawk1.23.1 -f delme.awk
DONE
222
```
