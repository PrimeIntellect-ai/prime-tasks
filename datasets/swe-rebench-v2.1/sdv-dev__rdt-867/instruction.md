`HyperTransformer` can’t detect `UInt` or `uint`
### Error Description

Currently `HyperTransformer` does not support `UInt` and `uint`. We should align the `HyperTransformer’s` detection with the metadata on sdv - https://github.com/sdv-dev/SDV/issues/2182


### Steps to reproduce

```python
import pandas as pd

data = {
    'Int8': pd.Series([1, 2, -3], dtype='Int8'),
    'Int16': pd.Series([1, 2, -3], dtype='Int16'),
    'Int32': pd.Series([1, 2, -3], dtype='Int32'),
    'Int64': pd.Series([1, 2, -3], dtype='Int64'),
    'UInt8': pd.Series([1, 2, 3], dtype='UInt8'),
    'UInt16': pd.Series([1, 2, 3], dtype='UInt16'),
    'UInt32': pd.Series([1, 2, 3], dtype='UInt32'),
    'UInt64': pd.Series([1, 2, 3], dtype='UInt64'),
    'Float32': pd.Series([1.1, 2.2, 3.3], dtype='Float32'),
    'Float64': pd.Series([1.1, 2.2, 3.3], dtype='Float64'),
    'boolean': pd.Series([True, False, None], dtype='boolean'),
}

df = pd.DataFrame(data)

from rdt import HyperTransformer

ht = HyperTransformer()

ht.detect_initial_config(df)
---------------------------------------------------------------------------
KeyError                                  Traceback (most recent call last)
Cell In[18], line 1
----> 1 ht.detect_initial_config(df)

File ~/.virtualenvs/SDV/lib/python3.8/site-packages/rdt/hyper_transformer.py:635, in HyperTransformer.detect_initial_config(self, data)
    633 # Set the sdtypes and transformers of all fields to their defaults
    634 LOGGER.info('Detecting a new config from the data ... SUCCESS')
--> 635 self._learn_config(data)
    637 LOGGER.info('Setting the new config ... SUCCESS')
    639 config = Config({
    640     'sdtypes': self.field_sdtypes,
    641     'transformers': self.field_transformers,
    642 })

File ~/.virtualenvs/SDV/lib/python3.8/site-packages/rdt/hyper_transformer.py:612, in HyperTransformer._learn_config(self, data)
    610 for field in data:
    611     if field not in self.field_sdtypes:
--> 612         self._set_field_sdtype(data, field)
    613     if field not in self.field_transformers:
    614         sdtype = self.field_sdtypes[field]

File ~/.virtualenvs/SDV/lib/python3.8/site-packages/rdt/hyper_transformer.py:598, in HyperTransformer._set_field_sdtype(self, data, field)
    596 clean_data = data[field].dropna()
    597 kind = clean_data.infer_objects().dtype.kind
--> 598 [HIDDEN]

KeyError: 'u'
```

### Expected Behavior

We should support the `uint` and `UInt` numerical data types. This `dtype` should use the `FloatFormatter` as default.
