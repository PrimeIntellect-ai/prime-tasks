When pretty-printing, add a space immediately after fieldname:
Currently, pretty-printing {total:dollars::45} produces:
```
{
  total:dollars::45
}
```
This becomes more readable if a space is added after total:, as in:
```
{
  total: dollars::45
}
```
