[Bug]: Langfuse Integration Error: TypeError: cannot pickle '_thread.RLock' object
### What happened

When using the Langfuse integration with litellm.log_langfuse_v2, a TypeError: cannot pickle '_thread.RLock' object is raised during the logging process. This appears to be caused by attempting to deepcopy data containing a _thread.RLock object, which is not serializable.

### To Reproduce

While the exact steps to reproduce may vary depending on the specific data being logged, the general pattern involves:

Using `success_callback: [langfuse]` to log data to Langfuse.
The data being logged (directly or within nested structures) contains a _thread.RLock object.

### Expected behavior

The Langfuse integration should successfully log data without raising a TypeError. Ideally, the integration should handle non-serializable objects gracefully.

### Environment

Python version:  v3.11.8
litellm version: 1.49.6 (from 2024-10-17)
langfuse version: v2.85.1 OSS

### Additional context

It seems that this issue was introduced very recently. The error traceback points to the [HIDDEN] as the source of the issue. This suggests that the integration attempts to create a deep copy of the data being logged, which fails due to the presence of the non-serializable _thread.RLock object.

Maybe a similar fix as in #3384 can be applied?

### Relevant log output

```shell
{"message": "Langfuse Layer Error - Traceback (most recent call last):\n File "/usr/local/lib/python3.11/site-packages/litellm/integrations/langfuse.py", line 373, in _log_langfuse_v2\n optional_params.pop("metadata")\nKeyError: 'metadata'\n\nDuring handling of the above exception, another exception occurred:\n\nTraceback (most recent call last):\n File "/usr/local/lib/python3.11/site-packages/litellm/integrations/langfuse.py", line 387, in _log_langfuse_v2\n [HIDDEN]\n ^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 206, in _deepcopy_list\n append(deepcopy(a, memo))\n ^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 172, in deepcopy\n y = _reconstruct(x, memo, *rv)\n ^^^^^^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 271, in _reconstruct\n state = deepcopy(state, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 172, in deepcopy\n y = _reconstruct(x, memo, *rv)\n ^^^^^^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 271, in _reconstruct\n state = deepcopy(state, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 172, in deepcopy\n y = _reconstruct(x, memo, *rv)\n ^^^^^^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 271, in _reconstruct\n state = deepcopy(state, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 172, in deepcopy\n y = _reconstruct(x, memo, *rv)\n ^^^^^^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 271, in _reconstruct\n state = deepcopy(state, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 172, in deepcopy\n y = _reconstruct(x, memo, *rv)\n ^^^^^^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 271, in _reconstruct\n state = deepcopy(state, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 172, in deepcopy\n y = _reconstruct(x, memo, *rv)\n ^^^^^^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 271, in _reconstruct\n state = deepcopy(state, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 146, in deepcopy\n y = copier(x, memo)\n ^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 231, in _deepcopy_dict\n y[deepcopy(key, memo)] = deepcopy(value, memo)\n ^^^^^^^^^^^^^^^^^^^^^\n File "/usr/local/lib/python3.11/copy.py", line 161, in deepcopy\n rv = reductor(4)\n ^^^^^^^^^^^\nTypeError: cannot pickle '_thread.RLock' object\n", "level": "ERROR", "timestamp": "2024-10-17T16:37:06.593106"}
```


### Twitter / LinkedIn details

_No response_
