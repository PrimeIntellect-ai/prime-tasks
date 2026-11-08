FS regex [^,]* fails on empty field
For example:

```
$ echo 'x,,z' | goawk -F'[^,]*' '{for (i=1;i<=NF;i++) print i, "<"$i">"}'
1 <>
2 <,>
3 <,>
4 <>

# Should be (and other AWKs print):
$ echo 'x,,z' | gawk -F'[^,]*' '{for (i=1;i<=NF;i++) print i, "<"$i">"}'
1 <>
2 <,,>
3 <>
```

See https://www.austingroupbugs.net/view.php?id=1468 (0001468).

Thanks @raygard for the report.
