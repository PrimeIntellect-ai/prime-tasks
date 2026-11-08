Empty hook file causes cryptic error
If you have a pre_gen_project.sh or a post_gen_project.sh file with no data in it, cookiecutter fails with an unhelpful traceback.

```
Traceback (most recent call last):
  File "/usr/local/bin/cookiecutter", line 11, in <module>
    sys.exit(main())
  File "/usr/local/lib/python2.7/site-packages/click/core.py", line 716, in __call__
    return self.main(*args, **kwargs)
  File "/usr/local/lib/python2.7/site-packages/click/core.py", line 696, in main
    rv = self.invoke(ctx)
  File "/usr/local/lib/python2.7/site-packages/click/core.py", line 889, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/usr/local/lib/python2.7/site-packages/click/core.py", line 534, in invoke
    return callback(*args, **kwargs)
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/cli.py", line 100, in main
    config_file=user_config
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/main.py", line 140, in cookiecutter
    output_dir=output_dir
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/generate.py", line 273, in generate_files
    _run_hook_from_repo_dir(repo_dir, 'pre_gen_project', project_dir, context)
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/generate.py", line 232, in _run_hook_from_repo_dir
    run_hook(hook_name, project_dir, context)
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/hooks.py", line 116, in run_hook
    run_script_with_context(script, project_dir, context)
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/hooks.py", line 101, in run_script_with_context
    run_script(temp.name, cwd)
  File "/usr/local/lib/python2.7/site-packages/cookiecutter/hooks.py", line 73, in run_script
    cwd=cwd
  File "/usr/local/Cellar/python/2.7.10_2/Frameworks/Python.framework/Versions/2.7/lib/python2.7/subprocess.py", line 656, in __init__
    _cleanup()
  File "/usr/local/Cellar/python/2.7.10_2/Frameworks/Python.framework/Versions/2.7/lib/python2.7/subprocess.py", line 1335, in _execute_child
    raise child_exception
OSError: [Errno 8] Exec format error
```

### Additional contract requirements

When an empty pre-generation or post-generation shell hook cannot be executed, Cookiecutter must report useful diagnostic information rather than exposing a cryptic execution traceback.
