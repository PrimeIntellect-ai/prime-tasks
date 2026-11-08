Pseudo-rich logger/printer sees colors
"[GCC]" is not a color command, but the logger would like to interpret it as such:

```python
[   40s] ____________________________ test_builder_printout _____________________________
[   40s]
[   40s] capsys = <_pytest.capture.CaptureFixture object at 0x7f704905b700>
[   40s]
[   40s]     def test_builder_printout(capsys):
[   40s] >       main()
[   40s]
[   40s] tests/test_printouts.py:5:
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s] ../../BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.10/site-packages/scikit_build_core/builder/__main__.py:21: in main
[   40s]     rich_print(f"[bold]Scikit-build-core {__version__}[/bold] on Python {sys.version}")
[   40s] ../../BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.10/site-packages/scikit_build_core/_logging.py:128: in rich_print
[   40s]     args_2 = tuple(_process_rich(arg) for arg in args)
[   40s] ../../BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.10/site-packages/scikit_build_core/_logging.py:128: in <genexpr>
[   40s]     args_2 = tuple(_process_rich(arg) for arg in args)
[   40s] ../../BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.10/site-packages/scikit_build_core/_logging.py:121: in _process_rich
[   40s]     return ANY_ESCAPE.sub(
[HIDDEN]
[   40s] _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
[   40s]
[   40s] .0 = <list_iterator object at 0x7f704905a860>
[   40s]
[HIDDEN]
[   40s]         str(msg),
[   40s]     )
[   40s] E   KeyError: 'GCC'
[   40s]
[   40s] ../../BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.10/site-packages/scikit_build_core/_logging.py:122: KeyError
```

```python
abuild@skylab:~> python3 -m scikit_build_core.builder.__main__
Traceback (most recent call last):
  File "<frozen runpy>", line 198, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "/home/abuild/rpmbuild/BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.11/site-packages/scikit_build_core/builder/__main__.py", line 39, in <module>
    main()
  File "/home/abuild/rpmbuild/BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.11/site-packages/scikit_build_core/builder/__main__.py", line 21, in main
    rich_print(f"[bold]Scikit-build-core {__version__}[/bold] on Python {sys.version}")
  File "/home/abuild/rpmbuild/BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.11/site-packages/scikit_build_core/_logging.py", line 128, in rich_print
    args_2 = tuple(_process_rich(arg) for arg in args)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/abuild/rpmbuild/BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.11/site-packages/scikit_build_core/_logging.py", line 128, in <genexpr>
    args_2 = tuple(_process_rich(arg) for arg in args)
                   ^^^^^^^^^^^^^^^^^^
  File "/home/abuild/rpmbuild/BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.11/site-packages/scikit_build_core/_logging.py", line 121, in _process_rich
    return ANY_ESCAPE.sub(
           ^^^^^^^^^^^^^^^
  [HIDDEN]
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/home/abuild/rpmbuild/BUILDROOT/python-scikit-build-core-0.9.5-0.x86_64/usr/lib/python3.11/site-packages/scikit_build_core/_logging.py", line 122, in <genexpr>
    [HIDDEN]
                      ~~~~~~~~^^^
KeyError: 'GCC'
abuild@skylab:~> python3 -c 'import sys; print(sys.version)'
3.11.9 (main, Apr 08 2024, 06:18:15) [GCC]
```
https://github.com/scikit-build/scikit-build-core/blob/7dd64ecea458bfa37d9ddcbc4f770024d3389939/src/scikit_build_core/_logging.py#L82
https://github.com/scikit-build/scikit-build-core/blob/7dd64ecea458bfa37d9ddcbc4f770024d3389939/src/scikit_build_core/_logging.py#L120-L124

### Additional contract requirements

- When printing text containing an unsupported pseudo-rich token, do not raise an error; preserve the token unchanged as literal text.
