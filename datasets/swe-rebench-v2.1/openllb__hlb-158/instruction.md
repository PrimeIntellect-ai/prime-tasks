comment at end of file causes parse error
input:
```
# this is ok
fs default() {
	scratch
}
# this is not ok
```

error:
```
$ ./hlb run ./bug.hlb
./bug.hlb:5:1: unable to parse
```

I have run into this a few times as I comment out the last function in a file while debugging and then suddenly get parse errors.

### Additional contract requirements

- When `Module.String()` unparses `fs foo() { scratch; } fs bar() { scratch; }`, the declarations must be separated by exactly one blank line: `fs foo() { scratch; }\n\nfs bar() { scratch; }`.
