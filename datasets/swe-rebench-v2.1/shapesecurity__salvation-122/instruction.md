Policy intersection and union should be case insensitive.
intersect:
```java
Policy p = parse("default-src 'self' example.com; ");
Policy q = parse("default-src 'self' EXAMPLE.COM; ");
p.intersect(q);
```
will result following policy ` default-src 'self'` instead of `default-src 'self' example.com;` or `default-src 'self' EXAMPLE.COM;`

in case of union:
```java
Policy p = parse("default-src 'self' example.com; ");
Policy q = parse("default-src 'self' EXAMPLE.COM; ");
p.union(q);
```
result is the `default-src 'self' example.com EXAMPLE.COM` but it should be `default-src 'self' example.com;` or `default-src 'self' EXAMPLE.COM;`

I'm not sure about lowercase vs UPPERCASE or even vs CaMeLcAsE in result of intersect or union, but I would just leave it in lowercase.
