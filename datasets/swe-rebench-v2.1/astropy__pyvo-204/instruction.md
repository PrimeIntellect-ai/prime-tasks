pyvo.io.vosi.vodataservice.DataType.__repr__ references attribute that doesn't exist
When trying to do a simple iteration over tables and columns for a TAP service I am getting errors when printing the column datatype.

Here is what I'm trying to do:
```
import pyvo as vo

tap_service = vo.dal.TAPService("http://vao.stsci.edu/zmast/tapservice.aspx")
print(tap_service.describe())
for table in (tap_service.tables):
    print(table.name, table.type, table.utype)
    print("Table:", table.description)
    for column in table.columns:
            print("Datatype:", column.datatype)
            print("Name:", column.name)
            if column.description is not None:
                print("Description:", column.description)
            print("Unit:", column.unit)

```

Here is the error:

```
Traceback (most recent call last):
  File "mast/z/scripts/schema_to_meta.py", line 12, in <module>
    print(column.datatype)
  File "/Users/sweissman/anaconda3/envs/z-mast/lib/python3.6/site-packages/pyvo/io/vosi/vodataservice.py", line 714, in __repr__
    self.arraysize, self.value)
AttributeError: 'VOTableType' object has no attribute 'value'

```

The issue appears to be with __repr__ referencing an attribute that doesn't exist:
https://github.com/astropy/pyvo/blob/7dfc90da1c82702fdb37d05b69d8db25057c0ae2/pyvo/io/vosi/vodataservice.py#L715-L717
