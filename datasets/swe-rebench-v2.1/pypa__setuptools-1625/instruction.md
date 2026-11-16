AssertionError on len(sdists) == 1 when sdist format is zip
In some Windows projects, users expect sdists to be released in zip form. For that reason, I've added the following to a project's setup.cfg:

```
[sdist]
formats=zip
```

With this setting in place, performing a `pep517.build .` on such a project results in the following traceback:

```
Traceback (most recent call last):
  File "/Users/jaraco/code/main/jaraco.video/.tox/release/lib/python3.7/site-packages/pep517/_in_process.py", line 207, in <module>
    main()
  File "/Users/jaraco/code/main/jaraco.video/.tox/release/lib/python3.7/site-packages/pep517/_in_process.py", line 197, in main
    json_out['return_val'] = hook(**hook_input['kwargs'])
  File "/Users/jaraco/code/main/jaraco.video/.tox/release/lib/python3.7/site-packages/pep517/_in_process.py", line 170, in build_sdist
    return backend.build_sdist(sdist_directory, config_settings)
  File "/var/folders/c6/v7hnmq453xb6p2dbz1gqc6rr0000gn/T/pep517-build-env-rgz_zb4_/lib/python3.7/site-packages/setuptools/build_meta.py", line 181, in build_sdist
    assert len(sdists) == 1
AssertionError
```

Even though the output from building the sdist was seen above. I suspect the builder expects the sdist to have a particular extension.

### Additional contract requirements

- A PEP 517 sdist build must produce a gztar archive, even when the project configures `[sdist] formats=zip`.
