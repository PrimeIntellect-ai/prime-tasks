0.4.0: --outdir fails when parent directory does not exist
```console
+ cd rich-10.4.0
+ /usr/bin/python3 -m build --no-isolation --outdir build/lib
Traceback (most recent call last):
  File "/usr/lib64/python3.8/runpy.py", line 194, in _run_module_as_main
    return _run_code(code, main_globals, None,
  File "/usr/lib64/python3.8/runpy.py", line 87, in _run_code
    exec(code, run_globals)
  File "/usr/lib/python3.8/site-packages/build/__main__.py", line 236, in <module>
    main(sys.argv[1:], 'python -m build')
  File "/usr/lib/python3.8/site-packages/build/__main__.py", line 228, in main
    build_package(args.srcdir, outdir, distributions, config_settings, not args.no_isolation, args.skip_dependency_check)
  File "/usr/lib/python3.8/site-packages/build/__main__.py", line 107, in build_package
    _build_in_current_env(builder, outdir, distributions, config_settings, skip_dependency_check)
  File "/usr/lib/python3.8/site-packages/build/__main__.py", line 84, in _build_in_current_env
    builder.build(dist, outdir, config_settings)
  File "/usr/lib/python3.8/site-packages/build/__init__.py", line 330, in build
    return self._call_backend(build, output_directory, config_settings, **kwargs)
  File "/usr/lib/python3.8/site-packages/build/__init__.py", line 340, in _call_backend
    [HIDDEN]
FileNotFoundError: [Errno 2] No such file or directory: '/home/tkloczko/rpmbuild/BUILD/rich-10.4.0/build/lib'
```

### Additional contract requirements

- The build path used by the CLI, `ProjectBuilder.build(distribution, outdir, config_settings=None, metadata_directory=None)`, must also create `outdir` and any missing parent directories before invoking the backend hook, so that `python -m build --outdir build/lib` succeeds when `build/lib` does not exist.
