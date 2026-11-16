pydev debugger: CRITICAL WARNING
Create Python project, and debug it via

```
lean backtest ".\My Project\" --debug ptvsd
```

We get the following message in the console:

```
20240429 17:53:54.923 TRACE:: DebuggerHelper.Initialize(): waiting for PTVSD debugger to attach at localhost:5678...
-------------------------------------------------------------------------------
pydev debugger: CRITICAL WARNING: This version of python seems to be incorrectly compiled (internal generated filenames
are not absolute)
pydev debugger: The debugger may still function, but it will work slower and may miss breakpoints.
pydev debugger: Related bug: http://bugs.python.org/issue1666807
-------------------------------------------------------------------------------
pydev debugger: Unable to find real location for: /root/.local/lib/python3.11/site-packages
pydev debugger: Unable to find real location for: <frozen posixpath>
pydev debugger: Unable to find real location for: <frozen genericpath>
pydev debugger: Unable to find real location for: <frozen abc>
pydev debugger: Unable to find real location for: <string>
20240429 17:54:08.036 TRACE:: DebuggerHelper.Initialize(): started
20240429 17:54:08.037 TRACE:: Config.GetValue(): algorithm-creation-timeout - Using default value: 90
20240429 17:54:08.047 TRACE:: AlgorithmPythonWrapper(): Python version 3.11.7 (main, Dec 15 2023, 18:24:52) [GCC
11.2.0]: Importing python module main
pydev debugger: Unable to find real location for: <frozen importlib._bootstrap>
pydev debugger: Unable to find real location for: <frozen importlib._bootstrap_external>
pydev debugger: Unable to find real location for: <frozen zipimport>
pydev debugger: Unable to find real location for: <frozen _collections_abc>
pydev debugger: Unable to find real location for: <frozen os>
pydev debugger: Unable to find real location for: <frozen io>
pydev debugger: Unable to find real location for: <frozen codecs>
```

We can attach the process and debug the
![Captura de ecrã 2024-04-29 185442](https://github.com/QuantConnect/lean-cli/assets/6889033/fc7e935b-30b4-401a-8673-398e718258cd)
algorithm:

### Additional contract requirements

- The `lean backtest` command's `--debug` option accepts the case-insensitive value `debugpy`, which selects the DebugPy debugging method.
- `DebuggingMethod.DebugPy` is a member of the `DebuggingMethod` enum in `lean.models.utils`.
- `DebuggingMethod.DebugPy.get_internal_name()` returns the string `"DebugPy"`.
- When a backtest is run with the DebugPy debugging method, the debugging port `5678` is exposed, exactly as it is for the PTVSD debugging method.
- When a backtest is started with the DebugPy debugging method, the VS Code launch configuration is updated so the debugger can attach, exactly as it is for the PTVSD debugging method.
