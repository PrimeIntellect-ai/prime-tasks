Set `License` metadata as well
I am not sure about what magic fedora uses with [their macro](https://src.fedoraproject.org/rpms/pyproject-rpm-macros/blob/f31/f/pyproject_save_files.py), but apparently it is able to auto-detect and mark python files as license files, e.g.:
```console
$ rpm -qpL python3-packit-0.75.0-1.fc38.noarch.rpm
/usr/lib/python3.11/site-packages/packitos-0.75.0.dist-info/licenses/LICENSE
```
But this does not work here:
```console
$ rpm -qpL python3-spglib-2.1.0.rc1-1.20230518123112228603.pr272.50.ge38c0dc.x86_64.rpm
warning: python3-spglib-2.1.0.rc1-1.20230518123112228603.pr272.50.ge38c0dc.x86_64.rpm: Header V4 RSA/SHA256 Signature, key ID bcf19e6e: NOKEY
```

My suspicion is because of the difference in `METADATA` file:
```
# packit
License-Expression: MIT
License-File: LICENSE
# spglib (where it doesn't detect)
License: BSD-3-Clause
```
Maybe the guys who showed me this feature can know more about it ([discussion](https://github.com/packit/packit/pull/1913#discussion_r1199132232))

Edit: Confirmed it is `License-File`.

### Additional contract requirements

- Every license file bundled into a built wheel must be identified in that wheel's `METADATA` by a `License-File` entry (for example `License-File: LICENSE`), and the file itself must be installed under the wheel's `.dist-info/licenses/` directory.
