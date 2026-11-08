[ "foo" = "fo*" ] should not have a pattern on the right side of the =
```console
$ brush --version
brush 0.2.14 (git:dd1d39c)

$ brush -c '[ "foo" = "fo?" ] && echo match || echo unmatch'
match

$ bash -c '[ "foo" = "fo?" ] && echo match || echo unmatch'
unmatch
```
