Dropping a table removes **all** indexes
Given the following queries:
```
On-disk database using BoltDB engine at path my.db.
genji> create table user(name text);
genji> create index idx_user_name on user(name);
genji> create table cars(brand text);
genji> create index idx_cars_brand on cars(brand);
```

Using `boltbrowser` I can see the indexes:

![image](https://user-images.githubusercontent.com/4570448/84804989-d4cfcc80-b003-11ea-8877-ffde284179aa.png)


If I remove the `cars` table:
```
genji> drop table cars;
```

⚠️    **All indexes get removed**:

![image](https://user-images.githubusercontent.com/4570448/84805103-09dc1f00-b004-11ea-9ffa-f16b21f1f834.png)

This is critical and should be fixed as soon as possible.
