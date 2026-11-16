Wrong code in _set_seed of BaseTransformer?
I am reading the code of SDV, and find the code
[_set_seed](https://github.com/sdv-dev/RDT/blob/main/rdt/transformers/base.py#L368)

It seems that for loop just concat the column name in the dataframe data, not the value in rows.

```
hash_value = self.columns[0]
        for value in data.head(5):
            hash_value += str(value)
```

maybe you want use the value in row like below?

```
hash_value = self.columns[0]
[HIDDEN]
```

### Additional contract requirements

- For deterministic seed derivation, use the column name followed by the string representations of the first five values in that column, in row order, concatenated without separators.
