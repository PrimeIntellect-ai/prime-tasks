Mrtrix3's DWIPreproc force inputs that are not mandatory
### Summary
The interface to Mrtrix3's dwifslpreproc forces some inputs that are not really necessary according to [the original CLI on which it relies](https://mrtrix.readthedocs.io/en/dev/reference/commands/dwifslpreproc.html).

### Actual behavior
The interface requires inputs to be set for out_grad_mrtrix, pe_dir, etc.

### Expected behavior
Ideally, it would change the necessary inputs (that are different and depends on the way you use this CLI).
A simpler solution would be to simply reduce the mandatory inputs to those that truly are.

python -c "import nipype; from pprint import pprint; pprint(nipype.get_info())"
-->

```
{'commit_hash': 'd77fc3c',
 'commit_source': 'installation',
 'networkx_version': '2.6.3',
 'nibabel_version': '3.2.1',
 'nipype_version': '1.8.0',
 'numpy_version': '1.20.0',
 'pkg_path': '/home/groot/Projects/PhD/venv/lib/python3.9/site-packages/nipype',
 'scipy_version': '1.7.3',
 'sys_executable': '/home/groot/Projects/PhD/venv/bin/python',
 'sys_platform': 'linux',
 'sys_version': '3.9.12 (main, Mar 24 2022, 16:20:11) \n[GCC 9.4.0]',
 'traits_version': '6.3.2'}
```

### Execution environment
- My python environment outside container

### Additional contract requirements

For `DWIPreproc`, callers must be able to omit both `out_grad_mrtrix` and `pe_dir` when building a command. These are the complete scope of the inputs whose requiredness is changed by this request; it does not change the requiredness of other inputs.
