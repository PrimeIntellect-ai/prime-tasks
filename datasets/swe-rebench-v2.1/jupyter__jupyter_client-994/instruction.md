When no kernel is found, jupter-run crashes with a traceback
Hello,
in Fedora, we use Automatic Bug Reporting Tool https://github.com/abrt/abrt

When a packaged software "crashes", the tool records that and encourages users to report it as a bug.

It also detects Python software that ends with a Traceback.

We have encountered an user report that running `/usr/bin/jupyter-run` with no kernel installed results in a Traceback and it is reported as a crash.

I tried reproducing this with pip-installed jupyter-client.

When I create a Python virtual environment on my machine and install jupyter-client in it, I cannot reproduce, because (presumably) it finds my kernels in /usr/share/jupyter/kernels/ and/or ~/.local/share/jupyter/kernels/.

However, if I use an empty podman container, I can reproduce:

```
$ podman run --rm -ti fedora:38 /usr/bin/bash
...
[root@cd03926c2bc1 /]# python3.11 -m venv venv
[root@cd03926c2bc1 /]# . venv/bin/activate
(venv) [root@cd03926c2bc1 /]# pip install jupyter-client
...
Successfully installed jupyter-client-8.4.0 jupyter-core-5.4.0 platformdirs-3.11.0 python-dateutil-2.8.2 pyzmq-25.1.1 six-1.16.0 tornado-6.3.3 traitlets-5.11.2

(venv) [root@cd03926c2bc1 /]# jupyter-run
[RunApp] WARNING | Kernelspec name python3 cannot be found!
[RunApp] ERROR | No such kernel named python3
Traceback (most recent call last):
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 85, in wrapper
    out = await method(self, *args, **kwargs)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 401, in _async_start_kernel
    kernel_cmd, kw = await self._async_pre_start_kernel(**kw)
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 363, in _async_pre_start_kernel
    self.kernel_spec,
    ^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 184, in kernel_spec
    self._kernel_spec = self.kernel_spec_manager.get_kernel_spec(self.kernel_name)
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/kernelspec.py", line 280, in get_kernel_spec
    raise NoSuchKernel(kernel_name)
jupyter_client.kernelspec.NoSuchKernel: No such kernel named python3
Traceback (most recent call last):
  File "/venv/bin/jupyter-run", line 8, in <module>
    sys.exit(RunApp.launch_instance())
             ^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_core/application.py", line 280, in launch_instance
    super().launch_instance(argv=argv, **kwargs)
  File "/venv/lib64/python3.11/site-packages/traitlets/config/application.py", line 1052, in launch_instance
    app.initialize(argv)
  File "/venv/lib64/python3.11/site-packages/traitlets/config/application.py", line 117, in inner
    return method(app, *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/runapp.py", line 71, in initialize
    JupyterConsoleApp.initialize(self)
  File "/venv/lib64/python3.11/site-packages/jupyter_client/consoleapp.py", line 366, in initialize
    self.init_kernel_manager()
  File "/venv/lib64/python3.11/site-packages/jupyter_client/consoleapp.py", line 319, in init_kernel_manager
    self.kernel_manager.start_kernel(**kwargs)
  File "/venv/lib64/python3.11/site-packages/jupyter_core/utils/__init__.py", line 173, in wrapped
    return loop.run_until_complete(inner)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib64/python3.11/asyncio/base_events.py", line 653, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 94, in wrapper
    raise e
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 85, in wrapper
    out = await method(self, *args, **kwargs)
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 401, in _async_start_kernel
    kernel_cmd, kw = await self._async_pre_start_kernel(**kw)
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 363, in _async_pre_start_kernel
    self.kernel_spec,
    ^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/manager.py", line 184, in kernel_spec
    self._kernel_spec = self.kernel_spec_manager.get_kernel_spec(self.kernel_name)
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/venv/lib64/python3.11/site-packages/jupyter_client/kernelspec.py", line 280, in get_kernel_spec
    raise NoSuchKernel(kernel_name)
```

Would it be possible to not show the traceback in this case and simply end the app when `[RunApp] ERROR | No such kernel named python3` is displayed, with a non-zero exit code?
