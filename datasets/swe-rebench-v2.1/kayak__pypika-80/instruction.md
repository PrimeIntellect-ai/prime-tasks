Cannot use union result as a subquery
I've tried to use result of abc and efg tables as a subquery to calculate the average value from those union tables

```
 abc, efg = Tables('abc', 'efg')
 hij = Query.from_(abc).select(abc.t).union(Query.from_(efg).select(efg.t))
 q = Query.from_(hij).select(an.Avg(hij.t))
```

but actual query I get is

```
'SELECT AVG("sq0"."t") FROM (SELECT "t" FROM "abc") "sq0"'
```

expected query should be

```
'SELECT AVG("sq0"."t") FROM ((SELECT "t" FROM "abc") UNION (SELECT "t" FROM "efg")) "sq0"'
```

Am I doing something wrong? or there is any other ways to achieve this.

Thanks
