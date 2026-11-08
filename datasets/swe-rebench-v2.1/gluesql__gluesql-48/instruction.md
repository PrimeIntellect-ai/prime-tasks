SELECT 1 FROM Test; not working
```sql
SELECT 1 + 1 FROM Test;
```
Above works, but...

```sql
SELECT 1 FROM Test;
```
This doesn't work with this error `[Blend Error] "FieldDefinitionNotSupported"`
