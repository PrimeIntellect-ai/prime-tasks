Single list element interpreted as string => error
Reported on JupyterLab Gitter by @mlucool

> Hello. What's the correct way to pass --LabApp.extra_labextensions_path=/path/to/dir on the CLI when there is exactly one extra path? Passing that gives "The 'app_dir' trait of a LabApp instance expected a unicode string, not the NoneType None.", but if I do --LabApp.extra_labextensions_path=/path/to/dir --LabApp.extra_labextensions_path=/dev/null it works as expected. More generally, how do you pass a traitlet list of a single value via CLI?

I opened #667 with a unit test that fails.
