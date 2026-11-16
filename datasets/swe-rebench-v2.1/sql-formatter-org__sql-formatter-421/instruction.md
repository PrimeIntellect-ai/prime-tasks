[FORMATTING] PLSQL incorrect format of "for update" syntax
Oracle sql text:
```
 select *  from andy.t_test for update;
```

Expect output:
```sql
 select *
   from andy.t_test for update;
```

output in demo website:
```sql
   select *
     from andy.t_test for
   update;
```
