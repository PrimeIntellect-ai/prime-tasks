Regression: UserWarning: Unexpected keys ['value'] in spec ...
our testing of dandi-cli against dev versions of hdmf and pynwb started to fail 2 days ago

https://github.com/dandi/dandi-cli/actions/runs/9772685521/job/26977490874

```
Run python -m pytest -s -v --cov=dandi --cov-report=xml dandi
ImportError while loading conftest '/home/runner/work/dandi-cli/dandi-cli/dandi/conftest.py'.
dandi/conftest.py:5: in <module>
    from .tests.fixtures import *  # noqa: F401, F403  # lgtm [py/polluting-import]
dandi/tests/fixtures.py:20: in <module>
    import pynwb
/opt/hostedtoolcache/Python/3.8.[18](https://github.com/dandi/dandi-cli/actions/runs/9772685521/job/26977490874#step:8:19)/x64/lib/python3.8/site-packages/pynwb/__init__.py:145: in <module>
    load_namespaces(__resources['namespace_path'])
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/utils.py:672: in func_call
    return func(**pargs)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/pynwb/__init__.py:139: in load_namespaces
    return __TYPE_MAP.load_namespaces(namespace_path)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/utils.py:668: in func_call
    return func(args[0], **pargs)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/build/manager.py:482: in load_namespaces
    deps = self.__ns_catalog.load_namespaces(**kwargs)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/utils.py:668: in func_call
    return func(args[0], **pargs)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/namespace.py:537: in load_namespaces
    ret[ns['name']] = self.__load_namespace(ns, reader, resolve=resolve)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/namespace.py:447: in __load_namespace
    self.__load_spec_file(reader, s['source'], catalog, types_to_load=types_to_load, resolve=resolve)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/namespace.py:401: in __load_spec_file
    temp_dict = {k: None for k in __reg_spec(self.__group_spec_cls, spec_dict)}
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/namespace.py:387: in __reg_spec
    spec_obj = spec_cls.build_spec(spec_dict)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/spec.py:93: in build_spec
    vargs = cls.build_const_args(spec_dict)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/pynwb/spec.py:105: in build_const_args
    ret = proxy.build_const_args(spec_dict)
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/spec.py:1385: in build_const_args
    ret['datasets'] = list(map(cls.dataset_spec_cls().build_spec, ret['datasets']))
/opt/hostedtoolcache/Python/3.8.18/x64/lib/python3.8/site-packages/hdmf/spec/spec.py:102: in build_spec
    warn(f'Unexpected keys {unused_vargs} in spec {spec_dict}')
E   UserWarning: Unexpected keys ['value'] in spec {'name': 'bias_current', 'dtype': 'float[32](https://github.com/dandi/dandi-cli/actions/runs/9772685521/job/26977490874#step:8:33)', 'value': 0.0, 'doc': 'Bias current, in amps, fixed to 0.0.'}
```

### Additional contract requirements

When a dataset specification is built from a dictionary containing a `value` key, preserve that configured value in the resulting specification and do not report it as an unexpected key.
