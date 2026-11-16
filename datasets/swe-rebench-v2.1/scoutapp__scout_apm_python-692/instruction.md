TypeError: '_NamespacePath' object is not subscriptable
Looks like it was related to this change: https://github.com/scoutapp/scout_apm_python/pull/668/files

I'm not entirely sure what causes this.
We're also using a custom integration, incase thats a factor.

The particular module it is trying to load (when we get the exception) is `repoze.who.middleware`

We've not made changes to our integration, and has been breaking since, 2.21, but is also happening on 2.23.2

Below is a stack trace, starting from when we run `.install()`

Please let me know if theres anything else I can provide, I'm not sure how to debug this further

```
scout_apm.api.install(config=scout_config)
File "/usr/local/lib/python3.7/site-packages/scout_apm/compat.py", line 142, in wrapper
 return func(*args, **kwargs)
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/__init__.py", line 45, in install
 launched = CoreAgentManager().launch()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/agent/manager.py", line 49, in launch
 self.download()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/agent/manager.py", line 58, in download
 self.downloader.download()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/agent/manager.py", line 161, in download
 downloaded = self.download_package()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/agent/manager.py", line 209, in download_package
 "GET", full_url, preload_content=False, timeout=10.0, retries=3
File "/usr/local/lib/python3.7/site-packages/urllib3/request.py", line 75, in request
 method, url, fields=fields, headers=headers, **urlopen_kw
File "/usr/local/lib/python3.7/site-packages/urllib3/request.py", line 96, in request_encode_url
 return self.urlopen(method, url, **extra_kw)
File "/usr/local/lib/python3.7/site-packages/urllib3/poolmanager.py", line 375, in urlopen
 response = conn.urlopen(method, u.request_uri, **kw)
File "/usr/local/lib/python3.7/site-packages/scout_apm/instruments/urllib3.py", line 68, in wrapped_urlopen
 return wrapped(*args, **kwargs)
File "/usr/local/lib/python3.7/contextlib.py", line 119, in __exit__
 next(self.gen)
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/tracked_request.py", line 134, in span
 self.stop_span()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/tracked_request.py", line 122, in stop_span
 stopping_span.annotate()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/tracked_request.py", line 258, in annotate
 self.capture_backtrace()
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/tracked_request.py", line 293, in capture_backtrace
 self.tag("stack", backtrace.capture_backtrace())
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/backtrace.py", line 122, in capture_backtrace
 return list(itertools.islice(walker, LIMIT))
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/backtrace.py", line 24, in filter_frames
 for frame in frames:
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/backtrace.py", line 84, in backtrace_walker
 yield {"file": filepath(frame), "line": lineno, "function": name}
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/backtrace.py", line 63, in filepath
 return module_filepath(module, filepath)
File "/usr/local/lib/python3.7/site-packages/scout_apm/core/backtrace.py", line 40, in module_filepath
 [HIDDEN]
TypeError: '_NamespacePath' object is not subscriptable
```

### Additional contract requirements

- Backtrace filepath processing must not raise when it encounters a module with a non-indexable namespace path, as reported for `repoze.who.middleware`.
