gh: prefix doesn't work anymore
* Cookiecutter version: 1.5.1
* Template project url: `gh:*`
* Python version: 2.7.13
* Operating System: Linux

### Description:

cookiecutter does not honor prefixes anymore.

### What I've run:

Simply testing the example from the README doesn't work as expected:

``` bash
$ cookiecutter gh:audreyr/cookiecutter-pypackage
A valid repository for "gh:audreyr/cookiecutter-pypackage" could not be found in the following locations:
gh:audreyr/cookiecutter-pypackage
/home/me/.cookiecutters/gh:audreyr/cookiecutter-pypackage
```
The same commands using the full repository path works as expected:

```bash
$ cookiecutter https://github.com/audreyr/cookiecutter-pypackage
```

### Additional contract requirements

- Add a public function `merge_configs(default: dict, overwrite: dict) -> dict` in module `cookiecutter.config`. It recursively merges `overwrite` into `default`: nested dictionaries are merged key by key, existing nested keys are preserved unless explicitly overridden, and non-dictionary values from `overwrite` replace those in `default`.
- When a user configuration file defines its own `abbreviations`, the built-in `gh`, `gl` and `bb` abbreviations must remain available, so that a template reference such as `gh:audreyr/cookiecutter-pypackage` still resolves to the corresponding GitHub URL.


- - Expanding `gh:audreyr/cookiecutter-pypackage` must return exactly `https://github.com/audreyr/cookiecutter-pypackage.git`.
