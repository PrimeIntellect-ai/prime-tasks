add Table.select?
Has allowing `Table` to `select`, eliminating the name to re-specify a table name with `from_` been considered? e.g.

```python
from pypika import Table, Query
t = Table('my_table')
t.select(t.x, t.y) == Query.from_('my_table').select(t.x, t.y) # -> True
```

Just an idea. Seems like it would add convenience when using from console/jupyter.

Thanks for your hard work on a great library!

### Additional contract requirements

- `Table.select(*terms)` must create a SELECT query whose FROM source is that table and whose selected terms are the supplied terms.
