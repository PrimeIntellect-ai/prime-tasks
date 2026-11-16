Cannot print `CustomLabelEncoder`: `ValueError`
### Environment Details

* RDT version: 1.2.1 (latest)
* Python version: Any
* Operating System: Any

### Error Description

There is an error any time the RDT library tries to print a `CustomLabelEncoder`. This affects my ability to inspect the config.

```python
customers = get_demo()
ht.detect_initial_config(data=customers)
transformer = CustomLabelEncoder(order=['VISA', 'AMEX', 'DISCOVER', None], add_noise=True)
ht.update_transformers({'credit_card': transformer})

ht.get_config() # error
print(transformer) # same error
```

```
ValueError: The truth value of a Series is ambiguous. Use a.empty, a.bool(), a.item(), a.any() or a.all().
```
(See below for Stack trace)

### Expected Output
It may be tricky to print all the values that the user has inputted as categories, especially if there are a lot of them and if there are a mix of types. The string representation can just include the word `<CUSTOM>` for now.

```python
>>> transformer = CustomLabelEncoder(order=['a', 'b', 'c', 'd', 'e', 'f', 'g', True, False, None], add_noise=True)
>>> print(transformer)
CustomLabelEncoder(order=<CUSTOM>, add_noise=True)
```

### Stack Trace

```
---------------------------------------------------------------------------
ValueError                                Traceback (most recent call last)
[/usr/local/lib/python3.8/dist-packages/IPython/core/formatters.py](https://localhost:8080/#) in __call__(self, obj)
    700                 type_pprinters=self.type_printers,
    701                 deferred_pprinters=self.deferred_printers)
--> 702             printer.pretty(obj)
    703             printer.flush()
    704             return stream.getvalue()

5 frames
[/usr/local/lib/python3.8/dist-packages/IPython/lib/pretty.py](https://localhost:8080/#) in pretty(self, obj)
    400                         if cls is not object \
    401                                 and callable(cls.__dict__.get('__repr__')):
--> 402                             return _repr_pprint(obj, self, cycle)
    403
    404             return _default_pprint(obj, self, cycle)

[/usr/local/lib/python3.8/dist-packages/IPython/lib/pretty.py](https://localhost:8080/#) in _repr_pprint(obj, p, cycle)
    695     """A pprint that just redirects to the normal repr function."""
    696     # Find newlines and replace them with p.break_()
--> 697     output = repr(obj)
    698     for idx,output_line in enumerate(output.splitlines()):
    699         if idx:

[/usr/local/lib/python3.8/dist-packages/rdt/hyper_transformer.py](https://localhost:8080/#) in __repr__(self)
     20         config = {
     21             'sdtypes': self['sdtypes'],
---> 22             'transformers': {k: repr(v) for k, v in self['transformers'].items()}
     23         }
     24

[/usr/local/lib/python3.8/dist-packages/rdt/hyper_transformer.py](https://localhost:8080/#) in <dictcomp>(.0)
     20         config = {
     21             'sdtypes': self['sdtypes'],
---> 22             'transformers': {k: repr(v) for k, v in self['transformers'].items()}
     23         }
     24

[/usr/local/lib/python3.8/dist-packages/rdt/transformers/base.py](https://localhost:8080/#) in __repr__(self)
    211
    212         for arg, value in instanced.items():
--> 213             [HIDDEN]
    214                 custom_args.append(f'{arg}={repr(value)}')
    215

[/usr/local/lib/python3.8/dist-packages/pandas/core/generic.py](https://localhost:8080/#) in __nonzero__(self)
   1535     @final
   1536     def __nonzero__(self):
-> 1537         raise ValueError(
   1538             f"The truth value of a {type(self).__name__} is ambiguous. "
   1539             "Use a.empty, a.bool(), a.item(), a.any() or a.all()."

ValueError: The truth value of a Series is ambiguous. Use a.empty, a.bool(), a.item(), a.any() or a.all().
```

### Additional contract requirements

Calling `repr` on the configuration returned by `HyperTransformer.get_config()` must succeed when that configuration contains a `CustomLabelEncoder`.
