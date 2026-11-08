Make create_anonymized_columns work with multi columns transformer
### Problem Description

The method `create_anonymized_columns` in `Hypertransformer` allows users to generate anonymized columns by providing the number of rows to generate and a list of columns. However, when one of the listed columns is part of a multi-column transformer, the method crashes with the following error:
```python
AttributeError: 'NoneType' object has no attribute 'is_generator'
```

### Expected Behavior

The method should be able to work with multi-column transformers, especially if the multi-column transformer is a generator. If the multi-column transformer is a generator, it should generate the data end-to-end without any issues.
