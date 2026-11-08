Bad field name when selecting a field using backquotes
```sql
genji> select `a` from foo;
{
  "`a`": 1
}
```

It should be:

```sql
genji> select `a` from foo;
{
  "a": null
}
genji> select `some "long" string` from foo;
{
  "some \"long\" string": null
}
```
