Import error for `nipype.interfaces.dipy.base`
### Summary

`import nipype.interfaces.dipy` generates an error for me, with Python 3.9 and 3.8, Dipy 4.12 (latest release) and latest release or current master of nipype.

### Actual behavior

Running the above import generates the error `TypeError: 'NoneType' object is not iterable` generated from `dipy_to_nipype_interface` at: https://github.com/nipy/nipype/blob/f756b71117493caea093bac79d576207d8f96482/nipype/interfaces/dipy/base.py#L200
[HIDDEN]

### How to replicate the behavior
- create a fresh venv
- pip install the latest dipy and nipype packages
- open python and run `import nipype.interfaces.dipy`

### Expected behavior

A working import. This seems an easy fix, if others can reproduce the issue I would be happy to make a PR replacing https://github.com/nipy/nipype/blob/f756b71117493caea093bac79d576207d8f96482/nipype/interfaces/dipy/base.py#L192 with:

```python
[HIDDEN]
```

### Platform details:

<!-- Please run the following code from your shell and place the output between the triple ticks, below.
python -c "import nipype; from pprint import pprint; pprint(nipype.get_info())"
-->

```
{'commit_hash': 'f756b7111',
 'commit_source': 'repository',
 'networkx_version': '2.6.3',
 'nibabel_version': '3.2.1',
 'nipype_version': '1.7.1-dev+gf756b7111',
 'numpy_version': '1.21.4',
 'pkg_path': '/home/.../basedir/nipype/nipype',
 'scipy_version': '1.7.2',
 'sys_executable': '/home/.../basedir/venv/bin/python',
 'sys_platform': 'linux',
 'sys_version': '3.9.9 (main, Nov 16 2021, 03:08:02) \n[GCC 9.3.0]',
 'traits_version': '6.3.2'}
```
(Error is the same for Python 3.8)

### Execution environment

- My python environment outside container

### Additional contract requirements

- Importing `nipype.interfaces.dipy` must succeed even when a discovered DIPY workflow has no default-valued run arguments.
