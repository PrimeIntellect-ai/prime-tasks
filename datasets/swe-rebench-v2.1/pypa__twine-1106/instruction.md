check: Error message No METADATA in archive when it's there
### Is there an existing issue for this?

- [X] I have searched the existing issues (open and closed), and could not find an existing issue

### What keywords did you use to search existing issues?

No Metadata in archive

### What operating system are you using?

macOS

### If you selected 'Other', describe your Operating System here

_No response_

### What version of Python are you running?

```console
3.12.3
```


### How did you install twine? Did you use your operating system's package manager or pip or something else?

```console
pipx install twine
```


### What version of twine do you have installed (include the complete output)

```console
5.0.0
```


### Which package repository are you using?

pypi.org

### Please describe the issue that you are experiencing

When running twine check on the attached wheel, it reports No METADATA in archive, even though it does have a METADATA file. Probably the issue is that the METADATA file is missing the requisite Metadata-Version field.

[coherent_build-0.0.1.dev0-py3-none-any.whl.zip](https://github.com/pypa/twine/files/15190464/coherent_build-0.0.1.dev0-py3-none-any.whl.zip)

Better would be to report an error message that indicates the true cause of the problem.


### Please list the steps required to reproduce this behaviour

Build an invalid wheel without minimal metadata. Run `twine check` on it.

### Anything else you'd like to mention?

_No response_

### Additional contract requirements

- For this case, the error message must include `No METADATA in archive or METADATA missing 'Metadata-Version': ` followed by the wheel file path.
