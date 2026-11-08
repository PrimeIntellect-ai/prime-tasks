TableSliceGroup.aggregate is failing when aggregating multiple columns
TableSliceGroup.aggregate is failing when aggregating multiple columns at once.

I added the following test to TableSliceGroupTest to show the issue.

```java
    @Test
    public void aggregateWithMultipleColumns() {
        table.addColumns(table.categoricalColumn("approval").copy().setName("approval2"));
        TableSliceGroup group = StandardTableSliceGroup.create(table, table.categoricalColumn("who"));
        Table aggregated = group.aggregate(ImmutableListMultimap.of("approval", exaggerate, "approval2", exaggerate));

        assertEquals(aggregated.rowCount(), group.size());
    }
```

Is failing with the following error:
```
java.lang.IllegalArgumentException: Column exageration [approval2] does not have the same number of rows as the other columns in the table.
```

### Additional contract requirements

When aggregating multiple requested columns, the returned table includes an aggregate result for every requested column and aggregation function. The returned table has one result row for each group.
