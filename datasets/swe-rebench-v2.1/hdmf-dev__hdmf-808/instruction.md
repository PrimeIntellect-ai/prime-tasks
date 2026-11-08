[Bug]: When exporting, cannot create a link to an object already in the file
### What happened?

I tried to read file A, create and add a new object (ImagingPlane) with a link to another object (Device) that already exists in A, and then export the new file B. In the new file B, rather than the link going internally to the object (Device) in file B, it goes to the object in file A.

[HIDDEN]

### Steps to Reproduce

```shell
See above.
```


### Traceback

```shell
n/a
```


### Operating System

Windows

### Python Executable

Conda

### Python Version

3.10

### Package Versions

_No response_

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](https://github.com/hdmf-dev/hdmf/blob/dev/.github/CODE_OF_CONDUCT.md)
- [X] Have you checked the [Contributing](https://github.com/hdmf-dev/hdmf/blob/dev/docs/CONTRIBUTING.rst) document?
- [X] Have you ensured this bug was not already [reported](https://github.com/hdmf-dev/hdmf/issues)?

### Additional contract requirements

When exporting to a new file, a newly added link to an object that already exists in the source file must resolve to that object's counterpart inside the exported file, rather than remaining linked to the source file. `HDF5IO.write_link` must accept `export_source` and use it to determine whether the link belongs inside the export.
