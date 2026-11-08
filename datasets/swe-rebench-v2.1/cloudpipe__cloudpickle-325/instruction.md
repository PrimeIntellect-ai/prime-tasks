With (I guess) update to scipy 1.4.0 test_dynamic_module and test_load_dynamic_module_in_grandchild_process break
When building packages for openSUSE I observe this:

* With Python 3.7.3, scipy 1.3.1, and cloudpickle 1.2.2 test suite passes without any problems

* With the same Python, same cloudpickle, but scipy 1.4.0 I get CloudPickleTest::test_dynamic_module, CloudPickleTest::test_load_dynamic_module_in_grandchild_process, Protocol2CloudPickleTest::test_dynamic_module, and Protocol2CloudPickleTest::test_load_dynamic_module_in_grandchild_process failing:

```
[   40s] =================================== FAILURES ===================================
[   40s] _____________________ CloudPickleTest.test_dynamic_module ______________________
[   40s]
[   40s] self = <tests.cloudpickle_test.CloudPickleTest testMethod=test_dynamic_module>
[   40s]
[   40s]     def test_dynamic_module(self):
[   40s]         mod = types.ModuleType('mod')
[   40s]         code = '''
[   40s]         x = 1
[   40s]         def f(y):
[   40s]             return x + y
[   40s]
[   40s]         class Foo:
[   40s]             def method(self, x):
[   40s]                 return f(x)
[   40s]         '''
[   40s]         exec(textwrap.dedent(code), mod.__dict__)
[   40s] >       mod2 = pickle_depickle(mod, protocol=self.protocol)
[   40s]
[   40s] tests/cloudpickle_test.py:474:
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s] tests/cloudpickle_test.py:67: in pickle_depickle
[   40s]     return pickle.loads(cloudpickle.dumps(obj, protocol=protocol))
[   40s] cloudpickle/cloudpickle.py:1125: in dumps
[   40s]     cp.dump(obj)
[   40s] cloudpickle/cloudpickle.py:482: in dump
[   40s]     return Pickler.dump(self, obj)
[   40s] /usr/lib64/python3.7/pickle.py:437: in dump
[   40s]     self.save(obj)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] cloudpickle/cloudpickle.py:507: in save_module
[   40s]     obj=obj)
[   40s] /usr/lib64/python3.7/pickle.py:638: in save_reduce
[   40s]     save(args)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:771: in save_tuple
[   40s]     save(element)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s]
[   40s] self = <cloudpickle.cloudpickle.CloudPickler object at 0x7f697bee6a20>
[   40s] obj = <capsule object NULL at 0x7f697cf9d660>, save_persistent_id = True
[   40s]
[   40s]     def save(self, obj, save_persistent_id=True):
[   40s]         self.framer.commit_frame()
[   40s]
[   40s]         # Check for persistent id (defined by a subclass)
[   40s]         pid = self.persistent_id(obj)
[   40s]         if pid is not None and save_persistent_id:
[   40s]             self.save_pers(pid)
[   40s]             return
[   40s]
[   40s]         # Check the memo
[   40s]         x = self.memo.get(id(obj))
[   40s]         if x is not None:
[   40s]             self.write(self.get(x[0]))
[   40s]             return
[   40s]
[   40s]         # Check the type dispatch table
[   40s]         t = type(obj)
[   40s]         f = self.dispatch.get(t)
[   40s]         if f is not None:
[   40s]             f(self, obj) # Call unbound method with explicit self
[   40s]             return
[   40s]
[   40s]         # Check private dispatch table if any, or else copyreg.dispatch_table
[   40s]         reduce = getattr(self, 'dispatch_table', dispatch_table).get(t)
[   40s]         if reduce is not None:
[   40s]             rv = reduce(obj)
[   40s]         else:
[   40s]             # Check for a class with a custom metaclass; treat as regular class
[   40s]             try:
[   40s]                 issc = issubclass(t, type)
[   40s]             except TypeError: # t is not a class (old Boost; see SF #502085)
[   40s]                 issc = False
[   40s]             if issc:
[   40s]                 self.save_global(obj)
[   40s]                 return
[   40s]
[   40s]             # Check for a __reduce_ex__ method, fall back to __reduce__
[   40s]             reduce = getattr(obj, "__reduce_ex__", None)
[   40s]             if reduce is not None:
[   40s] >               rv = reduce(self.proto)
[   40s] E               TypeError: can't pickle PyCapsule objects
[   40s]
[   40s] /usr/lib64/python3.7/pickle.py:524: TypeError
[   40s] ________ CloudPickleTest.test_load_dynamic_module_in_grandchild_process ________
[   40s]
[   40s] self = <tests.cloudpickle_test.CloudPickleTest testMethod=test_load_dynamic_module_in_grandchild_process>
[   40s]
[   40s]     def test_load_dynamic_module_in_grandchild_process(self):
[   40s]         # Make sure that when loaded, a dynamic module preserves its dynamic
[   40s]         # property. Otherwise, this will lead to an ImportError if pickled in
[   40s]         # the child process and reloaded in another one.
[   40s]
[   40s]         # We create a new dynamic module
[   40s]         mod = types.ModuleType('mod')
[   40s]         code = '''
[   40s]         x = 1
[   40s]         '''
[   40s]         exec(textwrap.dedent(code), mod.__dict__)
[   40s]
[   40s]         # This script will be ran in a separate child process. It will import
[   40s]         # the pickled dynamic module, and then re-pickle it under a new name.
[   40s]         # Finally, it will create a child process that will load the re-pickled
[   40s]         # dynamic module.
[   40s]         parent_process_module_file = os.path.join(
[   40s]             self.tmpdir, 'dynamic_module_from_parent_process.pkl')
[   40s]         child_process_module_file = os.path.join(
[   40s]             self.tmpdir, 'dynamic_module_from_child_process.pkl')
[   40s]         child_process_script = '''
[   40s]             import pickle
[   40s]             import textwrap
[   40s]
[   40s]             import cloudpickle
[   40s]             from testutils import assert_run_python_script
[   40s]
[   40s]
[   40s]             child_of_child_process_script = {child_of_child_process_script}
[   40s]
[   40s]             with open('{parent_process_module_file}', 'rb') as f:
[   40s]                 mod = pickle.load(f)
[   40s]
[   40s]             with open('{child_process_module_file}', 'wb') as f:
[   40s]                 cloudpickle.dump(mod, f, protocol={protocol})
[   40s]
[   40s]             assert_run_python_script(textwrap.dedent(child_of_child_process_script))
[   40s]             '''
[   40s]
[   40s]         # The script ran by the process created by the child process
[   40s]         child_of_child_process_script = """ '''
[   40s]                 import pickle
[   40s]                 with open('{child_process_module_file}','rb') as fid:
[   40s]                     mod = pickle.load(fid)
[   40s]                 ''' """
[   40s]
[   40s]         # Filling the two scripts with the pickled modules filepaths and,
[   40s]         # for the first child process, the script to be executed by its
[   40s]         # own child process.
[   40s]         child_of_child_process_script = child_of_child_process_script.format(
[   40s]                 child_process_module_file=child_process_module_file)
[   40s]
[   40s]         child_process_script = child_process_script.format(
[   40s]             parent_process_module_file=_escape(parent_process_module_file),
[   40s]             child_process_module_file=_escape(child_process_module_file),
[   40s]             child_of_child_process_script=_escape(child_of_child_process_script),
[   40s]             protocol=self.protocol)
[   40s]
[   40s]         try:
[   40s]             with open(parent_process_module_file, 'wb') as fid:
[   40s] >               cloudpickle.dump(mod, fid, protocol=self.protocol)
[   40s]
[   40s] tests/cloudpickle_test.py:591:
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s] cloudpickle/cloudpickle.py:1109: in dump
[   40s]     CloudPickler(file, protocol=protocol).dump(obj)
[   40s] cloudpickle/cloudpickle.py:482: in dump
[   40s]     return Pickler.dump(self, obj)
[   40s] /usr/lib64/python3.7/pickle.py:437: in dump
[   40s]     self.save(obj)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] cloudpickle/cloudpickle.py:507: in save_module
[   40s]     obj=obj)
[   40s] /usr/lib64/python3.7/pickle.py:638: in save_reduce
[   40s]     save(args)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:771: in save_tuple
[   40s]     save(element)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s]
[   40s] self = <cloudpickle.cloudpickle.CloudPickler object at 0x7f697ba60550>
[   40s] obj = <capsule object NULL at 0x7f697cf9d660>, save_persistent_id = True
[   40s]
[   40s]     def save(self, obj, save_persistent_id=True):
[   40s]         self.framer.commit_frame()
[   40s]
[   40s]         # Check for persistent id (defined by a subclass)
[   40s]         pid = self.persistent_id(obj)
[   40s]         if pid is not None and save_persistent_id:
[   40s]             self.save_pers(pid)
[   40s]             return
[   40s]
[   40s]         # Check the memo
[   40s]         x = self.memo.get(id(obj))
[   40s]         if x is not None:
[   40s]             self.write(self.get(x[0]))
[   40s]             return
[   40s]
[   40s]         # Check the type dispatch table
[   40s]         t = type(obj)
[   40s]         f = self.dispatch.get(t)
[   40s]         if f is not None:
[   40s]             f(self, obj) # Call unbound method with explicit self
[   40s]             return
[   40s]
[   40s]         # Check private dispatch table if any, or else copyreg.dispatch_table
[   40s]         reduce = getattr(self, 'dispatch_table', dispatch_table).get(t)
[   40s]         if reduce is not None:
[   40s]             rv = reduce(obj)
[   40s]         else:
[   40s]             # Check for a class with a custom metaclass; treat as regular class
[   40s]             try:
[   40s]                 issc = issubclass(t, type)
[   40s]             except TypeError: # t is not a class (old Boost; see SF #502085)
[   40s]                 issc = False
[   40s]             if issc:
[   40s]                 self.save_global(obj)
[   40s]                 return
[   40s]
[   40s]             # Check for a __reduce_ex__ method, fall back to __reduce__
[   40s]             reduce = getattr(obj, "__reduce_ex__", None)
[   40s]             if reduce is not None:
[   40s] >               rv = reduce(self.proto)
[   40s] E               TypeError: can't pickle PyCapsule objects
[   40s]
[   40s] /usr/lib64/python3.7/pickle.py:524: TypeError
[   40s] _________________ Protocol2CloudPickleTest.test_dynamic_module _________________
[   40s]
[   40s] self = <tests.cloudpickle_test.Protocol2CloudPickleTest testMethod=test_dynamic_module>
[   40s]
[   40s]     def test_dynamic_module(self):
[   40s]         mod = types.ModuleType('mod')
[   40s]         code = '''
[   40s]         x = 1
[   40s]         def f(y):
[   40s]             return x + y
[   40s]
[   40s]         class Foo:
[   40s]             def method(self, x):
[   40s]                 return f(x)
[   40s]         '''
[   40s]         exec(textwrap.dedent(code), mod.__dict__)
[   40s] >       mod2 = pickle_depickle(mod, protocol=self.protocol)
[   40s]
[   40s] tests/cloudpickle_test.py:474:
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s] tests/cloudpickle_test.py:67: in pickle_depickle
[   40s]     return pickle.loads(cloudpickle.dumps(obj, protocol=protocol))
[   40s] cloudpickle/cloudpickle.py:1125: in dumps
[   40s]     cp.dump(obj)
[   40s] cloudpickle/cloudpickle.py:482: in dump
[   40s]     return Pickler.dump(self, obj)
[   40s] /usr/lib64/python3.7/pickle.py:437: in dump
[   40s]     self.save(obj)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] cloudpickle/cloudpickle.py:507: in save_module
[   40s]     obj=obj)
[   40s] /usr/lib64/python3.7/pickle.py:638: in save_reduce
[   40s]     save(args)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:771: in save_tuple
[   40s]     save(element)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s]
[   40s] self = <cloudpickle.cloudpickle.CloudPickler object at 0x7f697be7ef98>
[   40s] obj = <capsule object NULL at 0x7f697cf9d660>, save_persistent_id = True
[   40s]
[   40s]     def save(self, obj, save_persistent_id=True):
[   40s]         self.framer.commit_frame()
[   40s]
[   40s]         # Check for persistent id (defined by a subclass)
[   40s]         pid = self.persistent_id(obj)
[   40s]         if pid is not None and save_persistent_id:
[   40s]             self.save_pers(pid)
[   40s]             return
[   40s]
[   40s]         # Check the memo
[   40s]         x = self.memo.get(id(obj))
[   40s]         if x is not None:
[   40s]             self.write(self.get(x[0]))
[   40s]             return
[   40s]
[   40s]         # Check the type dispatch table
[   40s]         t = type(obj)
[   40s]         f = self.dispatch.get(t)
[   40s]         if f is not None:
[   40s]             f(self, obj) # Call unbound method with explicit self
[   40s]             return
[   40s]
[   40s]         # Check private dispatch table if any, or else copyreg.dispatch_table
[   40s]         reduce = getattr(self, 'dispatch_table', dispatch_table).get(t)
[   40s]         if reduce is not None:
[   40s]             rv = reduce(obj)
[   40s]         else:
[   40s]             # Check for a class with a custom metaclass; treat as regular class
[   40s]             try:
[   40s]                 issc = issubclass(t, type)
[   40s]             except TypeError: # t is not a class (old Boost; see SF #502085)
[   40s]                 issc = False
[   40s]             if issc:
[   40s]                 self.save_global(obj)
[   40s]                 return
[   40s]
[   40s]             # Check for a __reduce_ex__ method, fall back to __reduce__
[   40s]             reduce = getattr(obj, "__reduce_ex__", None)
[   40s]             if reduce is not None:
[   40s] >               rv = reduce(self.proto)
[   40s] E               TypeError: can't pickle PyCapsule objects
[   40s]
[   40s] /usr/lib64/python3.7/pickle.py:524: TypeError
[   40s] ___ Protocol2CloudPickleTest.test_load_dynamic_module_in_grandchild_process ____
[   40s]
[   40s] self = <tests.cloudpickle_test.Protocol2CloudPickleTest testMethod=test_load_dynamic_module_in_grandchild_process>
[   40s]
[   40s]     def test_load_dynamic_module_in_grandchild_process(self):
[   40s]         # Make sure that when loaded, a dynamic module preserves its dynamic
[   40s]         # property. Otherwise, this will lead to an ImportError if pickled in
[   40s]         # the child process and reloaded in another one.
[   40s]
[   40s]         # We create a new dynamic module
[   40s]         mod = types.ModuleType('mod')
[   40s]         code = '''
[   40s]         x = 1
[   40s]         '''
[   40s]         exec(textwrap.dedent(code), mod.__dict__)
[   40s]
[   40s]         # This script will be ran in a separate child process. It will import
[   40s]         # the pickled dynamic module, and then re-pickle it under a new name.
[   40s]         # Finally, it will create a child process that will load the re-pickled
[   40s]         # dynamic module.
[   40s]         parent_process_module_file = os.path.join(
[   40s]             self.tmpdir, 'dynamic_module_from_parent_process.pkl')
[   40s]         child_process_module_file = os.path.join(
[   40s]             self.tmpdir, 'dynamic_module_from_child_process.pkl')
[   40s]         child_process_script = '''
[   40s]             import pickle
[   40s]             import textwrap
[   40s]
[   40s]             import cloudpickle
[   40s]             from testutils import assert_run_python_script
[   40s]
[   40s]
[   40s]             child_of_child_process_script = {child_of_child_process_script}
[   40s]
[   40s]             with open('{parent_process_module_file}', 'rb') as f:
[   40s]                 mod = pickle.load(f)
[   40s]
[   40s]             with open('{child_process_module_file}', 'wb') as f:
[   40s]                 cloudpickle.dump(mod, f, protocol={protocol})
[   40s]
[   40s]             assert_run_python_script(textwrap.dedent(child_of_child_process_script))
[   40s]             '''
[   40s]
[   40s]         # The script ran by the process created by the child process
[   40s]         child_of_child_process_script = """ '''
[   40s]                 import pickle
[   40s]                 with open('{child_process_module_file}','rb') as fid:
[   40s]                     mod = pickle.load(fid)
[   40s]                 ''' """
[   40s]
[   40s]         # Filling the two scripts with the pickled modules filepaths and,
[   40s]         # for the first child process, the script to be executed by its
[   40s]         # own child process.
[   40s]         child_of_child_process_script = child_of_child_process_script.format(
[   40s]                 child_process_module_file=child_process_module_file)
[   40s]
[   40s]         child_process_script = child_process_script.format(
[   40s]             parent_process_module_file=_escape(parent_process_module_file),
[   40s]             child_process_module_file=_escape(child_process_module_file),
[   40s]             child_of_child_process_script=_escape(child_of_child_process_script),
[   40s]             protocol=self.protocol)
[   40s]
[   40s]         try:
[   40s]             with open(parent_process_module_file, 'wb') as fid:
[   40s] >               cloudpickle.dump(mod, fid, protocol=self.protocol)
[   40s]
[   40s] tests/cloudpickle_test.py:591:
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s] cloudpickle/cloudpickle.py:1109: in dump
[   40s]     CloudPickler(file, protocol=protocol).dump(obj)
[   40s] cloudpickle/cloudpickle.py:482: in dump
[   40s]     return Pickler.dump(self, obj)
[   40s] /usr/lib64/python3.7/pickle.py:437: in dump
[   40s]     self.save(obj)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] cloudpickle/cloudpickle.py:507: in save_module
[   40s]     obj=obj)
[   40s] /usr/lib64/python3.7/pickle.py:638: in save_reduce
[   40s]     save(args)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:771: in save_tuple
[   40s]     save(element)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] /usr/lib64/python3.7/pickle.py:504: in save
[   40s]     f(self, obj) # Call unbound method with explicit self
[   40s] /usr/lib64/python3.7/pickle.py:856: in save_dict
[   40s]     self._batch_setitems(obj.items())
[   40s] /usr/lib64/python3.7/pickle.py:882: in _batch_setitems
[   40s]     save(v)
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s]
[   40s] self = <cloudpickle.cloudpickle.CloudPickler object at 0x7f697ba60978>
[   40s] obj = <capsule object NULL at 0x7f697cf9d660>, save_persistent_id = True
[   40s]
[   40s]     def save(self, obj, save_persistent_id=True):
[   40s]         self.framer.commit_frame()
[   40s]
[   40s]         # Check for persistent id (defined by a subclass)
[   40s]         pid = self.persistent_id(obj)
[   40s]         if pid is not None and save_persistent_id:
[   40s]             self.save_pers(pid)
[   40s]             return
[   40s]
[   40s]         # Check the memo
[   40s]         x = self.memo.get(id(obj))
[   40s]         if x is not None:
[   40s]             self.write(self.get(x[0]))
[   40s]             return
[   40s]
[   40s]         # Check the type dispatch table
[   40s]         t = type(obj)
[   40s]         f = self.dispatch.get(t)
[   40s]         if f is not None:
[   40s]             f(self, obj) # Call unbound method with explicit self
[   40s]             return
[   40s]
[   40s]         # Check private dispatch table if any, or else copyreg.dispatch_table
[   40s]         reduce = getattr(self, 'dispatch_table', dispatch_table).get(t)
[   40s]         if reduce is not None:
[   40s]             rv = reduce(obj)
[   40s]         else:
[   40s]             # Check for a class with a custom metaclass; treat as regular class
[   40s]             try:
[   40s]                 issc = issubclass(t, type)
[   40s]             except TypeError: # t is not a class (old Boost; see SF #502085)
[   40s]                 issc = False
[   40s]             if issc:
[   40s]                 self.save_global(obj)
[   40s]                 return
[   40s]
[   40s]             # Check for a __reduce_ex__ method, fall back to __reduce__
[   40s]             reduce = getattr(obj, "__reduce_ex__", None)
[   40s]             if reduce is not None:
[   40s] >               rv = reduce(self.proto)
[   40s] E               TypeError: can't pickle PyCapsule objects
[   40s]
[   40s] /usr/lib64/python3.7/pickle.py:524: TypeError
[   40s] =================== 4 failed, 174 passed, 7 skipped in 8.99s ===================
```
[Full build log](https://github.com/cloudpipe/cloudpickle/files/3983154/_log.txt) is attached as well.
