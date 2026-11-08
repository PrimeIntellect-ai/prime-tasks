ValuError sum_over must be False
Hi,
I am encountering a problem when trying to use upsetplot.
When I am running:
from upsetplot import from_memberships
example = from_memberships(
[[],
['set2'],
['set1'],
['set1', 'set2'],
['set0'],
['set0', 'set2'],
['set0', 'set1'],
['set0', 'set1', 'set2'],
],
data=[56,283,1279,5882,24,90,429,1957])

and then
from upsetplot import plot
plot(example)

An error appears:
ValueError: sum_over must be False or a column name when a DataFrame is input

When running example = generate_data(aggregated=True), plotting is working fine.
Please let me know, what the issue might be.

Thank you,
Vendi

### Additional contract requirements

The numeric-list example in the report must be usable as input to `plot(example)` without raising the `sum_over` ValueError described above.
