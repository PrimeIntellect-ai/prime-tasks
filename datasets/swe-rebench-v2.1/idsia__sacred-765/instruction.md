save_config with config_filename=mine.yaml fails
following similar things like the command line doc: https://sacred.readthedocs.io/en/stable/command_line.html

`python 2_hello_named_updates.py save_config with config_filename=mine.yaml` gives below error:

>WARNING - root - Added new config entry: "config_filename"
INFO - 2_hello_named_updates - Running command 'save_config'
INFO - 2_hello_named_updates - Started
ERROR - 2_hello_named_updates - Failed after 0:00:00!
Traceback (most recent calls WITHOUT Sacred internals):
sacred.utils.SacredError: The configuration is read-only in a captured function!

### Additional contract requirements

- The saved configuration must omit the `config_filename` entry.
