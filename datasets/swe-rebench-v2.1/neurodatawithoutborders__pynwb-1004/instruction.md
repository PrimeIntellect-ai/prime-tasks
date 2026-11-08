error when subject.date_of_birth is None
## 1) Bug

read has error when `Subject.date_of_birth` is `None`

If you are reporting a bug please provide the following:
### Steps to Reproduce
```python
from pynwb import NWBFile, NWBHDF5IO, get_manager, TimeSeries, ProcessingModule


fpath = '/path/to/EC2_B1.nwb'
with NWBHDF5IO(fpath, mode='r') as io:
    nwb = io.read()
```

```
---------------------------------------------------------------------------
AttributeError                            Traceback (most recent call last)
<ipython-input-1-9fdbf258d0d8> in <module>
      4 fpath = '/Volumes/black_backup/data/Chang/EC2/EC2_B1.nwb'
      5 with NWBHDF5IO(fpath, mode='r') as io:
----> 6     nwb = io.read()

~/dev/hdmf/src/hdmf/backends/hdf5/h5tools.py in read(self, **kwargs)
    244                                        % (self.__path, self.__mode))
    245         try:
--> 246             return call_docval_func(super(HDF5IO, self).read, kwargs)
    247         except UnsupportedOperation as e:
    248             if str(e) == 'Cannot build data. There are no values.':

~/dev/hdmf/src/hdmf/utils.py in call_docval_func(func, kwargs)
    279 def call_docval_func(func, kwargs):
    280     fargs, fkwargs = fmt_docval_args(func, kwargs)
--> 281     return func(*fargs, **fkwargs)
    282
    283

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/backends/io.py in read(self, **kwargs)
     33             # TODO also check that the keys are appropriate. print a better error message
     34             raise UnsupportedOperation('Cannot build data. There are no values.')
---> 35         container = self.__manager.construct(f_builder)
     36         return container
     37

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/build/map.py in construct(self, **kwargs)
    198         result = self.__containers.get(builder_id)
    199         if result is None:
--> 200             result = self.__type_map.construct(builder, self)
    201             parent_builder = self.__get_parent_dt_builder(builder)
    202             if parent_builder is not None:

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/build/map.py in construct(self, **kwargs)
   1683             raise ValueError('No ObjectMapper found for builder of type %s' % dt)
   1684         else:
-> 1685             return attr_map.construct(builder, build_manager)
   1686
   1687     @docval({"name": "container", "type": Container, "doc": "the container to convert to a Builder"},

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/build/map.py in construct(self, **kwargs)
   1181         cls = manager.get_cls(builder)
   1182         # gather all subspecs
-> 1183         subspecs = self.__get_subspec_values(builder, self.spec, manager)
   1184         # get the constructor argument that each specification corresponds to
   1185         const_args = dict()

~/dev/hdmf/src/hdmf/build/map.py in __get_subspec_values(self, builder, spec, manager)
   1125                         ret[subspec] = self.__flatten(sub_builder, subspec, manager)
   1126             # now process groups and datasets
-> 1127             self.__get_sub_builders(groups, spec.groups, manager, ret)
   1128             self.__get_sub_builders(datasets, spec.datasets, manager, ret)
   1129         elif isinstance(spec, DatasetSpec):

~/dev/hdmf/src/hdmf/build/map.py in __get_sub_builders(self, sub_builders, subspecs, manager, ret)
   1163                 if dt is None:
   1164                     # recurse
-> 1165                     ret.update(self.__get_subspec_values(sub_builder, subspec, manager))
   1166                 else:
   1167                     ret[subspec] = manager.construct(sub_builder)

~/dev/hdmf/src/hdmf/build/map.py in __get_subspec_values(self, builder, spec, manager)
   1125                         ret[subspec] = self.__flatten(sub_builder, subspec, manager)
   1126             # now process groups and datasets
-> 1127             self.__get_sub_builders(groups, spec.groups, manager, ret)
   1128             self.__get_sub_builders(datasets, spec.datasets, manager, ret)
   1129         elif isinstance(spec, DatasetSpec):

~/dev/hdmf/src/hdmf/build/map.py in __get_sub_builders(self, sub_builders, subspecs, manager, ret)
   1165                     ret.update(self.__get_subspec_values(sub_builder, subspec, manager))
   1166                 else:
-> 1167                     ret[subspec] = manager.construct(sub_builder)
   1168
   1169     def __flatten(self, sub_builder, subspec, manager):

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/build/map.py in construct(self, **kwargs)
    198         result = self.__containers.get(builder_id)
    199         if result is None:
--> 200             result = self.__type_map.construct(builder, self)
    201             parent_builder = self.__get_parent_dt_builder(builder)
    202             if parent_builder is not None:

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/build/map.py in construct(self, **kwargs)
   1683             raise ValueError('No ObjectMapper found for builder of type %s' % dt)
   1684         else:
-> 1685             return attr_map.construct(builder, build_manager)
   1686
   1687     @docval({"name": "container", "type": Container, "doc": "the container to convert to a Builder"},

~/dev/hdmf/src/hdmf/utils.py in func_call(*args, **kwargs)
    386                         raise_from(ExceptionType(msg), None)
    387
--> 388                 return func(self, **parsed['args'])
    389         else:
    390             def func_call(*args, **kwargs):

~/dev/hdmf/src/hdmf/build/map.py in construct(self, **kwargs)
   1196         for const_arg in get_docval(cls.__init__):
   1197             argname = const_arg['name']
-> 1198             override = self.__get_override_carg(argname, builder, manager)
   1199             if override is not None:
   1200                 val = override

~/dev/hdmf/src/hdmf/build/map.py in __get_override_carg(self, *args)
    689             try:
    690                 # remaining_args is [builder, manager]
--> 691                 return func(self, *remaining_args)
    692             except TypeError:
    693                 # LEGACY: remaining_args is [manager]

[HIDDEN]
     79     @ObjectMapper.constructor_arg('date_of_birth')
     80     def dateconversion(self, builder, manager):
---> 81         [HIDDEN]
     82         date = dateutil_parse(datestr)
     83         return date

AttributeError: 'NoneType' object has no attribute 'data'
```


### Environment
Please describe your environment according to the following bullet points.
- **Python Executable:** Conda or Python
- **Python Version:** Python 2.7 or Python 3.6
- **Operating System:** Windows, macOS or Linux
- **Pynwb Version:** Version of Pynwb used

## 2) Feature Request
If you are requesting a feature please provide the following:

### Problem/Use Case
Briefly describe the needed feature as well as the reasoning behind it

## Checklist

- [x] Have you ensured the feature or change was not already [reported](https://github.com/NeurodataWithoutBorders/pynwb/issues/) ?
- [x] Have you included a brief and descriptive title?
- [x] Have you included a clear description of the problem you are trying to solve?
- [x] Have you included a minimal code snippet that reproduces the issue you are encountering?
- [x] Have you checked our [Contributing](https://github.com/NeurodataWithoutBorders/pynwb/blob/dev/docs/CONTRIBUTING.rst) document?

### Additional contract requirements

- Reading an NWB file containing a `Subject` whose `date_of_birth` is `None` must succeed, and the reconstructed subject must retain `date_of_birth` as `None`.
