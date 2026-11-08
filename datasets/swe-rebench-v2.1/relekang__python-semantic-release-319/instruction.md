Github Action fails with v7.13.1
## The problem

When publishing my package using latest master I get the following error:

```
Run relekang/python-semantic-release@master
/usr/bin/docker run --name eb9cc679ae0e4f1f83d7f2d23985a34f_6e2f70 --label 442333 --workdir /github/workspace --rm -e INPUT_GITHUB_TOKEN -e INPUT_PYPI_TOKEN -e INPUT_DIRECTORY -e INPUT_PYPI_USERNAME -e INPUT_PYPI_PASSWORD -e HOME -e GITHUB_JOB -e GITHUB_REF -e GITHUB_SHA -e GITHUB_REPOSITORY -e GITHUB_REPOSITORY_OWNER -e GITHUB_RUN_ID -e GITHUB_RUN_NUMBER -e GITHUB_RETENTION_DAYS -e GITHUB_ACTOR -e GITHUB_WORKFLOW -e GITHUB_HEAD_REF -e GITHUB_BASE_REF -e GITHUB_EVENT_NAME -e GITHUB_SERVER_URL -e GITHUB_API_URL -e GITHUB_GRAPHQL_URL -e GITHUB_WORKSPACE -e GITHUB_ACTION -e GITHUB_EVENT_PATH -e GITHUB_ACTION_REPOSITORY -e GITHUB_ACTION_REF -e GITHUB_PATH -e GITHUB_ENV -e RUNNER_OS -e RUNNER_TOOL_CACHE -e RUNNER_TEMP -e RUNNER_WORKSPACE -e ACTIONS_RUNTIME_URL -e ACTIONS_RUNTIME_TOKEN -e ACTIONS_CACHE_URL -e GITHUB_ACTIONS=true -e CI=true -v "/var/run/docker.sock":"/var/run/docker.sock" -v "/home/runner/work/_temp/_github_home":"/github/home" -v "/home/runner/work/_temp/_github_workflow":"/github/workflow" -v "/home/runner/work/_temp/_runner_file_commands":"/github/file_commands" -v "/home/runner/work/arbie/arbie":"/github/workspace" 442333:eb9cc679ae0e4f1f83d7f2d23985a34f
Traceback (most recent call last):
  File "/usr/local/lib/python3.7/runpy.py", line 193, in _run_module_as_main
    "__main__", mod_spec)
  File "/usr/local/lib/python3.7/runpy.py", line 85, in _run_code
    exec(code, run_globals)
  File "/semantic-release/semantic_release/__main__.py", line 1, in <module>
    from .cli import entry
  File "/semantic-release/semantic_release/cli.py", line 13, in <module>
    from .changelog import markdown_changelog
  File "/semantic-release/semantic_release/changelog/__init__.py", line 4, in <module>
    from ..settings import config, current_changelog_components
  File "/semantic-release/semantic_release/settings.py", line 77, in <module>
    config = _config()
  File "/semantic-release/semantic_release/settings.py", line 29, in _config
    toml_config = _config_from_pyproject(toml_path)
  File "/semantic-release/semantic_release/settings.py", line 70, in _config_from_pyproject
    [HIDDEN]
TypeError: 'NoneType' object is not iterable
```

## Expected behavior

When I locked the version to using v7.12.0 the issue whent away.

## Additional context

I use python semantic release to deploy on a almost daily basis. Somethings must have broke in the last release.

Additional info:
* My config is located in setup.cfg and looks like this.
```
[semantic_release]
version_variable = Arbie/__init__.py:__version__
commit_subject = bump(version): Release v{version}
```
* When running on command-line `semantic-version publish --noop` seams to work.

The repository is not open source so I cannot share it. However let me know if more info is needed.

### Additional contract requirements

- If `pyproject.toml` has no `[tool.semantic_release]` section, configuration loading must not fail and applicable built-in defaults must remain available.
- In that case, values configured in `setup.cfg` under `[semantic_release]` must continue to be loaded and take effect.
