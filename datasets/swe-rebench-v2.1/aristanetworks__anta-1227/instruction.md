bug(anta): anta._runner module should not depend on anta.cli when used outside of ANTA CLI
```
  File "/home/ansible/.ansible/collections/ansible_collections/arista/avd/plugins/plugin_utils/eos_validate_state_utils/get_anta_results.py", line 47, in <module>
    from anta.runner import main as anta_runner
  File "/home/ansible/.local/lib/python3.10/site-packages/anta/runner.py", line 16, in <module>
    from anta._runner import AntaRunFilters, AntaRunner
  File "/home/ansible/.local/lib/python3.10/site-packages/anta/_runner.py", line 19, in <module>
    from anta.cli.console import console
  File "/home/ansible/.local/lib/python3.10/site-packages/anta/cli/__init__.py", line 15, in <module>
    from ._main import anta, cli
  File "/home/ansible/.local/lib/python3.10/site-packages/anta/cli/_main.py", line 15, in <module>
    from anta.cli.check import check as check_command
  File "/home/ansible/.local/lib/python3.10/site-packages/anta/cli/check/__init__.py", line 16, in <module>
    check.add_command(commands.catalog)
AttributeError: 'function' object has no attribute 'add_command'
```

Workaround is to make sure `anta[cli]` is also installed: https://anta.arista.com/stable/requirements-and-installation/#install-cli-from-pypi-server

### Additional contract requirements

- Importing and using the `anta._runner` module, including running tests through `AntaRunner.run`, must not require the `anta.cli` module to be installed or importable.
- The runner is the public class `AntaRunner` in the `anta._runner` module. It can run an inventory against a catalog, optionally applying filters and dry-run behavior, and returns an awaitable that completes the run.
- Device and tag filtering is the public class `AntaRunFilters` in `anta._runner`, constructed with optional `devices` and `tags` sets of strings.
- The run context is the public class `AntaRunContext` in `anta._runner`.
