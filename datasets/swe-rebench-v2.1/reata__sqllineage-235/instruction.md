Using JOIN with ON/USING keyword fails to determine source tables when followed by a parenthesis
I have the following queries:

```
create table target_table as (
    select *
    from source_table_a
    join source_table_b
    on (source_table_a.some_id = source_table_b.some_id))
)
```
```
create table target_table as (
    select *
    from source_table_a
    join source_table_b
    using (some_id)
)
```
This causes the table lineage to not extract `source_table_a` and `source_table_b` as sources. However, when the parenthesis are removed around `source_table_a.some_id = source_table_b.some_id)` and `some_id` it works properly.

Any help or insight would be greatly appreciated! 😀
