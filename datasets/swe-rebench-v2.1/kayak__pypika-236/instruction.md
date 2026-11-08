INSERT with subquery doesn't wrap with parentheses
Using v0.25.1, if I try to do an insert where one of the values is a subquery, pypika doesn't wrap the subquery in parentheses within the `VALUES` section.

```python
purchase_order_item = pypika.Table("purchase_order_item")
part = pypika.Table("part")

subquery = (
            pypika.MySQLQuery.from_(part)
            .select(part.part_id)
            .where(part.part_number == "FOOBAR")
        )

pypika.MySQLQuery.into(purchase_order_item).columns(purchase_order_item.id_part, purchase_order_item.id_customer).insert(subquery, 12345)
```

The above code generates this invalid query...
```sql
INSERT INTO `purchase_order_item`
(`id_part`,`id_customer`)
VALUES
(SELECT `part_id` FROM `part` WHERE `part_number`='FOOBAR',12345)
```

When it should be...
```sql
INSERT INTO `purchase_order_item`
(`id_part`,`id_customer`)
VALUES
((SELECT `part_id` FROM `part` WHERE `part_number`='FOOBAR'),12345)
```
