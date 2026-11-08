wrong syntax error message
With input:
```
fs default() {
        mkfile "foo" 0644 "content"
}
```
we see:
```
$ hlb run ./test.hlb
./test.hlb:2:2: expected 3 args, found 2
```

The arg count is not the problem, it is that hlb is not recognizing the `0644` input (typo, should be `0o644`) so the error message is confusing.
