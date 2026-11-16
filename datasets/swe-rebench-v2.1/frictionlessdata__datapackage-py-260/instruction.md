Package(schema='tabular') raises an Exception
To reproduce:

```python
import datapackage
dp = datapackage.Package(schema='tabular')
# Traceback (most recent call last):
#   File "<stdin>", line 1, in <module>
#   File "/home/vitor/Projetos/okfn/frictionlessdata/goodtables-py/env/lib/python3.6/site-packages/datapackage-1.1.4-py3.6.egg/datapackage/package.py", line 52, in __init__
#     descriptor['profile'] = schema
# TypeError: 'NoneType' object does not support item assignment
```
