_run_hook_from_repo_dir should not remove files if they already existed before
The current behavior makes `--overwrite-if-exists` remove all the files (undesirable) if some hook fails.

### Additional contract requirements

- For the existing-project undefined-variable cases, the file-name error message must be exactly `Unable to create file '{{cookiecutter.foobar}}'`. The directory-name error message must identify `testproject/{{cookiecutter.foobar}}`, using the platform-native path separator.
