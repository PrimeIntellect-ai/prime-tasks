Bug: Literal hex formatting can't handle underscores
This seems like a bug - it believes the underscores are digits, and so inadvertently changes the type by adding more digits.
```
$ echo "0xaa_aa_aa_aa" | runic
0x00000aa_aa_aa_aa
$ echo "0xaa_aa" | runic
0x000aa_aa
$ echo "0xaa" | runic
0xaa
```
