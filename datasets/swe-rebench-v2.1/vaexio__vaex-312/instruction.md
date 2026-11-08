vaex.groupby type casting
In the current implementation of `groupby`, if a column is on of type `int`, calculating the mean will also be of type `int`, which is numerically not accurate. This should probably be cased to `float` somewhere behind the scenes.
