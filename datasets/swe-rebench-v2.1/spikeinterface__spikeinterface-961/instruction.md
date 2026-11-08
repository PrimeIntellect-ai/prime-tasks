UnitsAggregationSorting fails to inherit property
Hi,

I saw in the `UnitsAggregationSorting` code that there is a copying of properties if they are consistent over all sortings.

However, look at the following code:

```python
sorting.annotate(name="Bonjour")
sorting.get_annotation("name")
> 'Bonjour'

sorting1 = sorting.select_units([0, 1])
sorting1.get_annotation("name")
> 'Bonjour'

sorting2 = sorting.select_units([unit_id for unit_id in sorting.unit_ids if unit_id != 0 and unit_id != 1])
sorting2.get_annotation("name")
> 'Bonjour'

new_sorting = si.UnitsAggregationSorting([sorting1, sorting2])
new_sorting.get_annotation("name")
> None
```

I believe the property should be inherited in this case.

Thanks,
Aurélien W.
