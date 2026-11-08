Python 3.7 can't pickle abc.AbstractClass
I had two test failures while trying to update the Debian cloudpickle package to 0.5.3 running with python 3.7.

```
cloudpickle/cloudpickle.py:645:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <cloudpickle.cloudpickle.CloudPickler object at 0x7f34d5fd1a58>
obj = <class 'abc.AbstractClass'>, name = 'AbstractClass'

    def save_global(self, obj, name=None):
        write = self.write
        memo = self.memo

        if name is None:
            name = getattr(obj, '__qualname__', None)
        if name is None:
            name = obj.__name__

        module_name = whichmodule(obj, name)
        try:
            __import__(module_name, level=0)
            module = sys.modules[module_name]
            obj2, parent = _getattribute(module, name)
        except (ImportError, KeyError, AttributeError):
            raise PicklingError(
                "Can't pickle %r: it's not found as %s.%s" %
>               (obj, module_name, name)) from None
E           _pickle.PicklingError: Can't pickle <class 'abc.AbstractClass'>: it's not found as abc.AbstractClass

/usr/lib/python3.7/pickle.py:957: PicklingError

During handling of the above exception, another exception occurred:
```
(exception during the exception cut for brevity)


```
self = <cloudpickle.cloudpickle.CloudPickler object at 0x7f34d5fd1a58>
obj = <_abc_data object at 0x7f34d5ff1f30>, save_persistent_id = True

    def save(self, obj, save_persistent_id=True):
        self.framer.commit_frame()

        # Check for persistent id (defined by a subclass)
        pid = self.persistent_id(obj)
        if pid is not None and save_persistent_id:
            self.save_pers(pid)
            return

        # Check the memo
        x = self.memo.get(id(obj))
        if x is not None:
            self.write(self.get(x[0]))
            return

        # Check the type dispatch table
        t = type(obj)
        f = self.dispatch.get(t)
        if f is not None:
            f(self, obj) # Call unbound method with explicit self
            return

        # Check private dispatch table if any, or else copyreg.dispatch_table
        reduce = getattr(self, 'dispatch_table', dispatch_table).get(t)
        if reduce is not None:
            rv = reduce(obj)
        else:
            # Check for a class with a custom metaclass; treat as regular class
            try:
                issc = issubclass(t, type)
            except TypeError: # t is not a class (old Boost; see SF #502085)
                issc = False
            if issc:
                self.save_global(obj)
                return

            # Check for a __reduce_ex__ method, fall back to __reduce__
            reduce = getattr(obj, "__reduce_ex__", None)
            if reduce is not None:
>               rv = reduce(self.proto)
E               TypeError: can't pickle _abc_data objects

/usr/lib/python3.7/pickle.py:524: TypeError
```
