Change to Set argv parsing behavior in 5.x?
I didn't see an existing issue for this yet, but with traitlets 5 release we had this reported in nbconvert: https://github.com/jupyter/nbconvert/issues/1410 related to set assignment from command line not working with the upgrade. Specifically `--TagRemovePreprocessor.remove_cell_tags={\"noeffect\"}` works with trailets 4 but not 5, though `[\"noeffect\"]` works in both for `remove_cell_tags = Set(Unicode())`.

Locally there isn't a problem with assigning from a set or a list inside a python process against a `Set` traitlet attribute. Tracing the issue further I got to https://github.com/jupyter/jupyter_core/blob/master/jupyter_core/application.py#L226 and it seems like the issue is in argv parsing changing behavior here.

Is there a new pattern expected for parse_command_line parsing for `Set` traits or now or is this a bug with this particular pattern?
