Error parsing $++a
Possibly related to https://github.com/benhoyt/goawk/issues/79, but opening a separate issue for visibility: GoAWK errors when parsing `$++a`. Compare:

```
$ echo -e '1 2 3\na b c\nd e f' | gawk '{ print $++a }'
1
b
f
$ echo -e '1 2 3\na b c\nd e f' | goawk '{ print $++a }'
<cmdline>:1:10: expected expression instead of ++
{ print $++a }
         ^
```

### Additional contract requirements

- For `BEGIN { ++3 }`, the parse error must be exactly `parse error at 1:11: expected lvalue after ++`.
- Also support parsing and executing `{ print $++n; print $--n }` with input `x y`; it must produce exactly `x\nx y\n`.
- When invoked with `-f -` and stdin containing `\n $`, report exactly `<stdin>:2:3: expected expression instead of <newline>\n $\n  ^`.
