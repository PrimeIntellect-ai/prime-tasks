conda pip interop AssertionError in 4.6.1
This is the error with the most reports for 4.6.1 (over 100 in the last 24 hours).  I've got a PR in the works to resolve this one.

```
error: AssertionError()
command: D:\Users\rahul\Anaconda3\Scripts\conda-script.py list
user_agent: conda/4.6.1 requests/2.18.4 CPython/3.6.5 Windows/10 Windows/10.0.17763
_messageid: -9223372036617369010
_messagetime: 1548792058544 / 2019-01-29 14:00:58

Traceback (most recent call last):
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\exceptions.py", line 1001, in __call__
    return func(*args, **kwargs)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\cli\main.py", line 84, in _main
    exit_code = do_call(args, p)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\cli\conda_argparse.py", line 81, in do_call
    exit_code = getattr(module, func_name)(args, parser)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\cli\main_list.py", line 142, in execute
    show_channel_urls=context.show_channel_urls)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\cli\main_list.py", line 80, in print_packages
    show_channel_urls=show_channel_urls)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\cli\main_list.py", line 45, in list_packages
    installed = sorted(PrefixData(prefix, pip_interop_enabled=True).iter_records(),
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\core\prefix_data.py", line 116, in iter_records
    return itervalues(self._prefix_records)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\core\prefix_data.py", line 145, in _prefix_records
    return self.__prefix_records or self.load() or self.__prefix_records
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\core\prefix_data.py", line 69, in load
    self._load_site_packages()
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\core\prefix_data.py", line 258, in _load_site_packages
    python_record = read_python_record(self.prefix_path, af, python_pkg_record.version)
  File "D:\Users\rahul\Anaconda3\lib\site-packages\conda\gateways\disk\read.py", line 245, in read_python_record
    pydist = PythonDistribution.init(prefix_path, anchor_file, python_version)
  [HIDDEN]
AssertionError
```

### Additional contract requirements

- When a mandatory metadata file is missing, constructing a `PythonInstalledDistribution` must raise `EnvironmentError` with `errno == ENOENT`.
- When pip interoperability encounters a discovered Python distribution with a missing mandatory metadata file, package listing must complete and preserve other valid installed records.
