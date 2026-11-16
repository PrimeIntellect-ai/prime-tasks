An inplace update which fails will still modify IDs
See below, this is unexpected behavior and the inplace operation should be rolled back

```
In [11]: print(biom.example_table)
# Constructed from biom file
#OTU ID	S1	S2	S3
O1	0.0	1.0	2.0
O2	3.0	4.0	5.0

In [12]: biom.example_table.update_ids({i: 'foo' for i in biom.example_table.ids()},
    ...:                               inplace=True)
---------------------------------------------------------------------------
TableException                            Traceback (most recent call last)
Cell In[12], line 1
----> 1 biom.example_table.update_ids({i: 'foo' for i in biom.example_table.ids()},
      2                               inplace=True)

File ~/miniconda3/envs/qiime2-2022.11/lib/python3.8/site-packages/biom/table.py:1428, in Table.update_ids(self, id_map, axis, strict, inplace)
   1424 result._index_ids(None, None)
   1426 # check for errors (specifically, we want to esnsure that duplicate
   1427 # ids haven't been introduced)
-> 1428 errcheck(result)
   1430 return result

File ~/miniconda3/envs/qiime2-2022.11/lib/python3.8/site-packages/biom/err.py:474, in errcheck(table, *errtypes)
    472 ret = __errprof.test(table, *errtypes)
    473 if isinstance(ret, Exception):
--> 474     raise ret
    475 else:
    476     return ret

TableException: Duplicate sample IDs!

In [13]: print(biom.example_table)
# Constructed from biom file
#OTU ID	foo	foo	foo
O1	0.0	1.0	2.0
O2	3.0	4.0	5.0
```
