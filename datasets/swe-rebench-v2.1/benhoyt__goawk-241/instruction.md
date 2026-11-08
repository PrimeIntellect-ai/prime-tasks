srand() initialization without an argument.
The POSIX spec for Awk states:

> `srand([expr])`:
> Set the seed value for rand to expr or use the time of day if expr is omitted. The previous seed value shall be returned.

This makes the expression `srand(srand())` a portable (if rather bizarre) idiom for obtaining the current unix epoch in pure Awk. `gawk`, `mawk`, and the "one-true" `awk` support this idiom, but `goawk` does not appear to:

```
% gawk 'BEGIN{print srand(srand())}'
1714957797
% goawk 'BEGIN{print srand(srand())}'
1
% goawk --version
v1.27.0
```

I think you would be within your rights to declare supporting this idiom undesirable, but I'm not aware of any alternatives that are fully POSIX-compliant. Shelling out to `date +%s`, for example, might seem reasonable, but `%s` as a `date` format character does not appear to be guaranteed as of POSIX 1003.1-2017. Thoughts?
