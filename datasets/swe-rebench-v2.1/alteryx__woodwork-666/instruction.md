Set time index adds tag to multiple columns after reset_semantic_tags call
If you try to set the time index after a call to reset the semantic tags on a dataframe, the `time_index` tag gets added to multiple columns and can return the wrong value for `df.ww.time_index`.

#### Code Sample

```python
>>> import woodwork as ww
>>> df = ww.demo.load_retail(nrows=100, return_dataframe=True)
df.ww.init(name="retail")
>>> df.ww.init(name="retail")
>>> df.ww.reset_semantic_tags()
>>> df.ww.set_time_index('order_date')
>>> df.ww.time_index
'description'
>>> df.ww
                   Physical Type     Logical Type Semantic Tag(s)
Column
order_product_id           Int64          Integer     ['numeric']
order_id                   Int64          Integer     ['numeric']
product_id              category      Categorical    ['category']
description               string  NaturalLanguage  ['time_index']
quantity                   Int64          Integer     ['numeric']
order_date        datetime64[ns]         Datetime  ['time_index']
unit_price               float64           Double     ['numeric']
customer_name             string  NaturalLanguage  ['time_index']
country                   string  NaturalLanguage  ['time_index']
total                    float64           Double     ['numeric']
cancelled                boolean          Boolean  ['time_index']
```
