[BUG] `dask` related failures
Some tests fail with a dask related issue, unclear source, direct at init of tests - FYI @yarnabrina, are these the failures you talked about?

Exampel: https://github.com/sktime/sktime/actions/runs/8613435074/job/23605843798?pr=6278

Traceback:
```
INTERNALERROR> Traceback (most recent call last):
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/_pytest/main.py", line 281, in wrap_session
INTERNALERROR>     config._do_configure()
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/_pytest/config/__init__.py", line 1121, in _do_configure
INTERNALERROR>     self.hook.pytest_configure.call_historic(kwargs=dict(config=self))
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/pluggy/_hooks.py", line 523, in call_historic
INTERNALERROR>     res = self._hookexec(self.name, self._hookimpls.copy(), kwargs, False)
INTERNALERROR>           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/pluggy/_manager.py", line 119, in _hookexec
INTERNALERROR>     return self._inner_hookexec(hook_name, methods, kwargs, firstresult)
INTERNALERROR>            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/pluggy/_callers.py", line 138, in _multicall
INTERNALERROR>     raise exception.with_traceback(exception.__traceback__)
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/pluggy/_callers.py", line 102, in _multicall
INTERNALERROR>     res = hook_impl.function(*args)
INTERNALERROR>           ^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/home/runner/work/sktime/sktime/conftest.py", line 51, in pytest_configure
INTERNALERROR>     from sktime.tests import test_all_estimators
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/__init__.py", line 7, in <module>
INTERNALERROR>     from sktime.utils._maint._show_versions import show_versions
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/utils/__init__.py", line 4, in <module>
INTERNALERROR>     from sktime.utils.plotting import plot_series, plot_windows
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/utils/plotting.py", line 14, in <module>
INTERNALERROR>     from sktime.datatypes import convert_to
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/__init__.py", line 5, in <module>
INTERNALERROR>     from sktime.datatypes._check import (
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_check.py", line 32, in <module>
INTERNALERROR>     from sktime.datatypes._hierarchical import check_dict_Hierarchical
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_hierarchical/__init__.py", line 3, in <module>
INTERNALERROR>     from sktime.datatypes._hierarchical._check import check_dict as check_dict_Hierarchical
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_hierarchical/_check.py", line 49, in <module>
INTERNALERROR>     from sktime.datatypes._panel._check import check_pdmultiindex_panel
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_panel/__init__.py", line 3, in <module>
INTERNALERROR>     from sktime.datatypes._panel._check import check_dict as check_dict_Panel
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_panel/_check.py", line 50, in <module>
INTERNALERROR>     from sktime.datatypes._series._check import (
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_series/__init__.py", line 5, in <module>
INTERNALERROR>     from sktime.datatypes._series._examples import example_dict as example_dict_Series
INTERNALERROR>   File "/home/runner/work/sktime/sktime/sktime/datatypes/_series/_examples.py", line 70, in <module>
INTERNALERROR>     from dask.dataframe import from_pandas
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/__init__.py", line 100, in <module>
INTERNALERROR>     from dask.dataframe import backends, dispatch, rolling
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/backends.py", line 15, in <module>
INTERNALERROR>     from dask.dataframe.core import DataFrame, Index, Scalar, Series, _Frame
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/core.py", line 36, in <module>
INTERNALERROR>     from dask.dataframe import methods
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/methods.py", line 34, in <module>
INTERNALERROR>     from dask.dataframe.utils import is_dataframe_like, is_index_like, is_series_like
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/utils.py", line 20, in <module>
INTERNALERROR>     from dask.dataframe import (  # noqa: F401 register pandas extension types
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/_dtypes.py", line 9, in <module>
INTERNALERROR>     from dask.dataframe.extensions import make_array_nonempty, make_scalar
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/extensions.py", line 8, in <module>
INTERNALERROR>     from dask.dataframe.accessor import (
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/accessor.py", line 126, in <module>
INTERNALERROR>     class DatetimeAccessor(Accessor):
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/accessor.py", line 81, in __init_subclass__
INTERNALERROR>     _bind_property(cls, pd_cls, attr, min_version)
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/dataframe/accessor.py", line 35, in _bind_property
INTERNALERROR>     setattr(cls, attr, property(derived_from(pd_cls, version=min_version)(func)))
INTERNALERROR>                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/utils.py", line 987, in wrapper
INTERNALERROR>     method.__doc__ = _derived_from(
INTERNALERROR>                      ^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/utils.py", line 940, in _derived_from
INTERNALERROR>     method_args = get_named_args(method)
INTERNALERROR>                   ^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/site-packages/dask/utils.py", line 701, in get_named_args
INTERNALERROR>     s = inspect.signature(func)
INTERNALERROR>         ^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/inspect.py", line 3263, in signature
INTERNALERROR>     return Signature.from_callable(obj, follow_wrapped=follow_wrapped,
INTERNALERROR>            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/inspect.py", line 3011, in from_callable
INTERNALERROR>     return _signature_from_callable(obj, sigcls=cls,
INTERNALERROR>            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/inspect.py", line 2599, in _signature_from_callable
INTERNALERROR>     call = _descriptor_get(call, obj)
INTERNALERROR>            ^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR>   File "/opt/hostedtoolcache/Python/3.11.9/x64/lib/python3.11/inspect.py", line 2432, in _descriptor_get
INTERNALERROR>     return get(descriptor, obj, type(obj))
INTERNALERROR>            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
INTERNALERROR> TypeError: descriptor '__call__' for 'type' objects doesn't apply to a 'property' object
```

### Additional contract requirements

Selecting the dataframe optional dependency must permit Dask 2024.4.1, the release line that resolves the reported import-time failure.
