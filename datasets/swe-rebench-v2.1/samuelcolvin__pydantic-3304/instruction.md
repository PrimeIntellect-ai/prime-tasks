Pydantic fails to read content of files in secrets_dir on Linux
### Checks

* [x] I added a descriptive title to this issue
* [x] I have searched (google, github) for similar issues and couldn't find anything
* [x] I have read and followed [the docs](https://pydantic-docs.helpmanual.io/) and still think this is a bug

<!-- Sorry to sound so draconian, but every second saved replying to issues is time spend improving pydantic :-) -->

# Bug

To reproduce, on Linux OS:
- build a config manager that subclasses `BaseSettings`
- add `secrets_dir` config pointing to dir with text file(s), as per docs
- add class attributes to use the files in `secrets_dir`, as per docs
- run the code and inspect/print the attributes
- observe that vars coming from .env file work fine, but those from `secrets_dir` are None, or error if not Optional, and there is no user warning for the `secrets_dir` itself

Repeat the same on MacOS - it should work OK, the content is read correctly.

I have added a repo with Dockerfile replicating the setup: https://github.com/dimitri-b/pydantic-secrets-dir-issue

Output of `python -c "import pydantic.utils; print(pydantic.utils.version_info())"`:
```
             pydantic version: 1.8.2
            pydantic compiled: True
                 install path: /usr/local/lib/python3.8/site-packages/pydantic
               python version: 3.8.12 (default, Sep  3 2021, 02:35:42)  [GCC 8.3.0]
                     platform: Linux-5.10.47-linuxkit-x86_64-with-glibc2.2.5
     optional deps. installed: ['dotenv', 'typing-extensions']
```
<!-- or if you're using pydantic prior to v1.3, manually include: OS, python version and pydantic version -->

<!-- Please read the [docs](https://pydantic-docs.helpmanual.io/) and search through issues to
confirm your bug hasn't already been reported. -->

<!-- Where possible please include a self-contained code snippet describing your bug: -->


```py
import pydantic

class SettingsLocal(pydantic.BaseSettings):
    NORMAL_VAR: Optional[str]
    SECRET_VAR: Optional[str]

    class Config:
        env_file = "./.env"
        secrets_dir = "./secrets-in-project"
...
```

### Additional contract requirements

- Provide a public function `find_case_path(dir_path: Path, file_name: str, case_sensitive: bool) -> Optional[Path]` in `pydantic.env_settings`. It searches `dir_path` for a file whose name matches `file_name`: when `case_sensitive` is `True` the file name must match exactly, and when `case_sensitive` is `False` the match ignores case. It returns the matching `Path`, or `None` when no such file exists.
