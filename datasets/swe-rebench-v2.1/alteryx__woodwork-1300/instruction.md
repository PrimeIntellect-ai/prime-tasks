Setting new logical type with set_types drops user set semantic tags
Setting a new logical type with `set_types` can cause previously set semantic tags to be lost. This behavior seems a bit counter-intuitive when users do not specify new tags. If users do not specify new values for semantic tags during the call to `set_types` any previously set semantic tags should be retained.

### Current Behavior
Custom tag on `vals` column is lost
```python
import pandas as pd
import woodwork as ww

df = pd.DataFrame({'id': [0, 1, 2], 'vals': [True, False, True]})
df.ww.init(semantic_tags={'vals': 'custom_tag'})

df.ww
```
```
       Physical Type Logical Type Semantic Tag(s)
Column
id             int64      Integer     ['numeric']
vals            bool      Boolean  ['custom_tag']
```
```python
df.ww.set_types({'vals': 'boolean_nullable'})
df.ww
```
```
       Physical Type     Logical Type Semantic Tag(s)
Column
id             int64          Integer     ['numeric']
vals         boolean  BooleanNullable              []
```

### Expected Behavior
Custom tag on `vals` column is retained
```python
import pandas as pd
import woodwork as ww

df = pd.DataFrame({'id': [0, 1, 2], 'vals': [True, False, True]})
df.ww.init(semantic_tags={'vals': 'custom_tag'})

df.ww
```
```
       Physical Type Logical Type Semantic Tag(s)
Column
id             int64      Integer     ['numeric']
vals            bool      Boolean  ['custom_tag']
```
```python
df.ww.set_types({'vals': 'boolean_nullable'})
df.ww
```
```
       Physical Type     Logical Type Semantic Tag(s)
Column
id             int64          Integer     ['numeric']
vals         boolean  BooleanNullable  ['custom_tag']
```
