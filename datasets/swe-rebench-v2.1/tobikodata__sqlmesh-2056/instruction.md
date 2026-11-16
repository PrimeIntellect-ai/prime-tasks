Adding a comment to an `AUDIT` sql file fails to load it
Adding a comment to an `AUDIT` sql file:

```sql
-- Some comment
AUDIT (
  name assert_order_items_quantity_exceeds_threshold
);

SELECT *
FROM @this_model
WHERE quantity <= @quantity
```

Will fail to load it with the following error:

```
Error: Invalid extra fields {'description'} in the audit definition at 'examples/sushi/audits/order_items.sql'
```
