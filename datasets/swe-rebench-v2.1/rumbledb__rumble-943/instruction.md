Exception when grouping with keys of different types
The following query will throw an exception that should not be thrown:
```
for $x in ("1", 49) group by $x return $x

(:  "eq": operation not possible with parameters of type "xs:integer" and "xs:string" :)
```

The reason for that is the following:
`hashCode()` will map "1" to `49` (its ASCII representation) and will thus land in the same bucket as 49 (whose `hashCode()` is simply `49` as well). So far, this is fine.

[HIDDEN]
Expected result is `(1, 49)` or `(49, 1)` (depending on ordering).
