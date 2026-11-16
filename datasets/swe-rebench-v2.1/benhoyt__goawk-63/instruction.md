Add support for `getline < "-"` to read from stdin
gawk, mawk and the "one true awk" have support for this, and it seems reasonable considering that POSIX requires interpretation of `-` as stdin in basically all other areas.

Only issue is that read prompts in general are a bit awkward with #47. For example:
```
$ goawk 'BEGIN { ARGV[ARGC++] = "-"; print "Enter input:"; getline; print "You entered: " $0 }'
this is my input
Enter input:
You entered: this is my input
```

### Additional contract requirements

- Both the plain form `getline < "-"` and the variable form `getline var < "-"` read from stdin.
