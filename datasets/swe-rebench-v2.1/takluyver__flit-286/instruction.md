flit install --symlink doest not honor --python for scripts it installs
Hi,

I have been experimenting with flit recently and I very much like it's approach for development installs (`--symlink`).

I noticed what could be a small issues with such installations.

I have flit installed globally (with pipx).

When I try to install my project with `pip install --symlink --python $(which python)` in a virtualenv, I notice the installed script uses flit's python as shebang instead of the python of the virtualenv.

[HIDDEN]
