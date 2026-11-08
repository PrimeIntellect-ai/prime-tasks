Pandas series with object type get converted to strings
This error is a slightly different take on https://github.com/jsonpickle/jsonpickle/issues/407 and https://github.com/jsonpickle/jsonpickle/issues/358.

My issue is that if a dataframe has a column of mixed type (e.g. `[4, 'foo']`), then it will be converted to strings on unpickling (e.g. `['4', 'foo']`):

```py
import pandas as pd
import jsonpickle as jp
import jsonpickle.ext.numpy as jsonpickle_numpy
import jsonpickle.ext.pandas as jsonpickle_pandas
jsonpickle_numpy.register_handlers()
jsonpickle_pandas.register_handlers()

# Create simple data frame of mixed data types
df1 = pd.DataFrame((
  a = [1, 2],
  b = [4, 'foo']
))

# Convert to jsonpickle
string = jp.dumps(df1)
df2 = jp.loads(string)

# Show that it didn't work
print(df1.b.values)
print(df2.b.values)

assert df1.b[0] == df2.b[0] # False: the first is 4 and the second is '4'
```

I know there isn't an easy fix for this, but I'm hopeful that there's _some_ fix, since (at least in this case) the actual dataframe data looks a lot like JSON format already! In particular, one suggestion I have is that currently just a single `dtype` is stored per column:
```py
"meta": {"dtypes": {"a": "int64", "b": "object"}
```

[HIDDEN]

Personally, I also think storing `values` as a dict of lists (rather than as a string) would be more robust _and_ easier to read/interpret. I feel `pd.DataFrame.to_dict()` is already pretty close to what would be required!

### Additional contract requirements

- A jsonpickle round trip of a DataFrame with a mixed-type column must preserve each element’s value and type, rather than coercing an element to another type (for example, converting an integer to a string).
