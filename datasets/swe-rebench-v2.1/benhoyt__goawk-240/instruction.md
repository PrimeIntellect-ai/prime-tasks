Support for %i in format strings.
The [POSIX spec](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap05.html#tag_05) permits using `%i` as an alternative to `%d`. This is supported by most awk implementations:
```
% awk 'BEGIN{printf("%i\n",42)}'
42
% mawk 'BEGIN{printf("%i\n",42)}'
42
% gawk 'BEGIN{printf("%i\n",42)}'
42
```

GoAWK v1.27.0 does not interpret `%i` correctly:
```
% goawk 'BEGIN{printf("%i\n",42)}'
%!i(int=42)
```
