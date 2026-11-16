Implement more detailed `__lt__` for component sorting
Components on a block are sorted by their `getBoundingCircleOuterDiameter`.

https://github.com/terrapower/armi/blob/abd1db4adfa0c536f9bf9f08f0f1e8b74b1cd0d7/armi/reactor/components/component.py#L272-L288

Sometimes, two components have the same outer diameter, in which case the sorting done by `__lt__` will depend on the order of comparison. i.e.,

`a < b` evaluates to `False`
`b < a` also evaluates to `False`

As a result,

`sorted([a, b]) = [a, b]`
while
`sorted([b, a]) = [b, a]`

Ideally, the outcome of `sorted` will not be dependent on the order of the input.

We should fall back to `getCircleInnerDiameter` for comparison when sorting components when `getBoundingCircleOuterDiameter` is equivalent. I pushed an example of what I think the sorting should do here:

https://github.com/terrapower/armi/compare/main...component_sort
