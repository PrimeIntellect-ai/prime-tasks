OFFSET and LIMIT are applied in the wrong order
Example:

```python
    def test_select_with_limit_and_offset(self):
        q1 = Query.from_('abc').select('foo')[10:10]

        self.assertEqual('SELECT "foo" FROM "abc" OFFSET 10 LIMIT 10', str(q1))
```

The query should actually be `SELECT "foo" FROM "abc" LIMIT 10 OFFSET 10`
