Print/repr of df fails after join
I am encountering an issue in which i can not `display/print/repr` a DataFrame after join.
I believe the join works successfully, you can view individual rows, and use their methods (`unique`, `value_counts` etc..) but not display the entire DataFrame.

I tried, but I could not reproduce the error with a small synthetic data, and the data I am using the far to large to append here (100s of millions or samples).

The most I can narrow it down is this:
- only occurs for `how="left"` and `how="right"`. Everything works well for `how="inner"`;
- no filtering. selections etc is done on either the left or the right dataframe
- joining is done on a string column
- there are repeated keys in the left dataframe
- there are keys in the index column on the left dataframe that are not in the right and vice versa
- the length of the joined dataframe is as expected (see traceback)

The traceback is this:
```
---------------------------------------------------------------------------
AssertionError                            Traceback (most recent call last)
~/miniconda3/lib/python3.7/site-packages/IPython/core/formatters.py in __call__(self, obj, include, exclude)
    968
    969             if method is not None:
--> 970                 return method(include=include, exclude=exclude)
    971             return None
    972         else:

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _repr_mimebundle_(self, include, exclude, **kwargs)
   3451         # TODO: optimize, since we use the same data in both versions
   3452         # TODO: include latex version
-> 3453         return {'text/html':self._head_and_tail_table(format='html'), 'text/plain': self._head_and_tail_table(format='plain')}
   3454
   3455     def _repr_html_(self):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _head_and_tail_table(self, n, format)
   3260             return self._as_table(0, N, format=format)
   3261         else:
-> 3262             return self._as_table(0, n, N - n, N, format=format)
   3263
   3264     def head_and_tail_print(self, n=5):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _as_table(self, i1, i2, j1, j2, format)
   3376                 # parts += ["</tr>"]
   3377             # return values_list
-> 3378         parts = table_part(i1, i2, parts)
   3379         if j1 is not None and j2 is not None:
   3380             values_list[0][1].append('...')

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in table_part(k1, k2, parts)
   3354             # slicing will invoke .extract which will make the evaluation
   3355             # much quicker
-> 3356             df = self[k1:k2]
   3357             for i, name in enumerate(column_names):
   3358                 try:

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in __getitem__(self, item)
   4306                 df = self.extract()
   4307                 df.set_active_range(start, stop)
-> 4308             return df.trim()
   4309
   4310     def __delitem__(self, item):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in trim(self, inplace)
   3623                         df.columns[name] = column[self._index_start:self._index_end]
   3624                     else:
-> 3625                         df.columns[name] = column.trim(self._index_start, self._index_end)
   3626         df._length_original = self.length_unfiltered()
   3627         df._length_unfiltered = df._length_original

~/Work/vaex/packages/vaex-core/vaex/column.py in trim(self, i1, i2)
    105
    106     def trim(self, i1, i2):
--> 107         return ColumnIndexed(self.df, self.indices[i1:i2], self.name)
    108
    109     def __getitem__(self, slice):

~/Work/vaex/packages/vaex-core/vaex/column.py in __init__(self, df, indices, name)
     75         self.shape = (len(indices),)
     76         max_index = self.indices.max()
---> 77         [HIDDEN]
     78
     79     @staticmethod

AssertionError:

---------------------------------------------------------------------------
AssertionError                            Traceback (most recent call last)
~/miniconda3/lib/python3.7/site-packages/IPython/core/formatters.py in __call__(self, obj)
    700                 type_pprinters=self.type_printers,
    701                 deferred_pprinters=self.deferred_printers)
--> 702             printer.pretty(obj)
    703             printer.flush()
    704             return stream.getvalue()

~/miniconda3/lib/python3.7/site-packages/IPython/lib/pretty.py in pretty(self, obj)
    400                         if cls is not object \
    401                                 and callable(cls.__dict__.get('__repr__')):
--> 402                             return _repr_pprint(obj, self, cycle)
    403
    404             return _default_pprint(obj, self, cycle)

~/miniconda3/lib/python3.7/site-packages/IPython/lib/pretty.py in _repr_pprint(obj, p, cycle)
    695     """A pprint that just redirects to the normal repr function."""
    696     # Find newlines and replace them with p.break_()
--> 697     output = repr(obj)
    698     for idx,output_line in enumerate(output.splitlines()):
    699         if idx:

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in __repr__(self)
   3462
   3463     def __repr__(self):
-> 3464         return self._head_and_tail_table(format='plain')
   3465
   3466     def __current_sequence_index(self):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _head_and_tail_table(self, n, format)
   3260             return self._as_table(0, N, format=format)
   3261         else:
-> 3262             return self._as_table(0, n, N - n, N, format=format)
   3263
   3264     def head_and_tail_print(self, n=5):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _as_table(self, i1, i2, j1, j2, format)
   3376                 # parts += ["</tr>"]
   3377             # return values_list
-> 3378         parts = table_part(i1, i2, parts)
   3379         if j1 is not None and j2 is not None:
   3380             values_list[0][1].append('...')

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in table_part(k1, k2, parts)
   3354             # slicing will invoke .extract which will make the evaluation
   3355             # much quicker
-> 3356             df = self[k1:k2]
   3357             for i, name in enumerate(column_names):
   3358                 try:

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in __getitem__(self, item)
   4306                 df = self.extract()
   4307                 df.set_active_range(start, stop)
-> 4308             return df.trim()
   4309
   4310     def __delitem__(self, item):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in trim(self, inplace)
   3623                         df.columns[name] = column[self._index_start:self._index_end]
   3624                     else:
-> 3625                         df.columns[name] = column.trim(self._index_start, self._index_end)
   3626         df._length_original = self.length_unfiltered()
   3627         df._length_unfiltered = df._length_original

~/Work/vaex/packages/vaex-core/vaex/column.py in trim(self, i1, i2)
    105
    106     def trim(self, i1, i2):
--> 107         return ColumnIndexed(self.df, self.indices[i1:i2], self.name)
    108
    109     def __getitem__(self, slice):

~/Work/vaex/packages/vaex-core/vaex/column.py in __init__(self, df, indices, name)
     75         self.shape = (len(indices),)
     76         max_index = self.indices.max()
---> 77         [HIDDEN]
     78
     79     @staticmethod

AssertionError:

---------------------------------------------------------------------------
AssertionError                            Traceback (most recent call last)
~/miniconda3/lib/python3.7/site-packages/IPython/core/formatters.py in __call__(self, obj)
    343             method = get_real_method(obj, self.print_method)
    344             if method is not None:
--> 345                 return method()
    346             return None
    347         else:

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _repr_html_(self)
   3456         """Representation for Jupyter."""
   3457         self._output_css()
-> 3458         return self._head_and_tail_table()
   3459
   3460     def __str__(self):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _head_and_tail_table(self, n, format)
   3260             return self._as_table(0, N, format=format)
   3261         else:
-> 3262             return self._as_table(0, n, N - n, N, format=format)
   3263
   3264     def head_and_tail_print(self, n=5):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in _as_table(self, i1, i2, j1, j2, format)
   3376                 # parts += ["</tr>"]
   3377             # return values_list
-> 3378         parts = table_part(i1, i2, parts)
   3379         if j1 is not None and j2 is not None:
   3380             values_list[0][1].append('...')

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in table_part(k1, k2, parts)
   3354             # slicing will invoke .extract which will make the evaluation
   3355             # much quicker
-> 3356             df = self[k1:k2]
   3357             for i, name in enumerate(column_names):
   3358                 try:

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in __getitem__(self, item)
   4306                 df = self.extract()
   4307                 df.set_active_range(start, stop)
-> 4308             return df.trim()
   4309
   4310     def __delitem__(self, item):

~/Work/vaex/packages/vaex-core/vaex/dataframe.py in trim(self, inplace)
   3623                         df.columns[name] = column[self._index_start:self._index_end]
   3624                     else:
-> 3625                         df.columns[name] = column.trim(self._index_start, self._index_end)
   3626         df._length_original = self.length_unfiltered()
   3627         df._length_unfiltered = df._length_original

~/Work/vaex/packages/vaex-core/vaex/column.py in trim(self, i1, i2)
    105
    106     def trim(self, i1, i2):
--> 107         return ColumnIndexed(self.df, self.indices[i1:i2], self.name)
    108
    109     def __getitem__(self, slice):

~/Work/vaex/packages/vaex-core/vaex/column.py in __init__(self, df, indices, name)
     75         self.shape = (len(indices),)
     76         max_index = self.indices.max()
---> 77         [HIDDEN]
     78
     79     @staticmethod

AssertionError:

```
