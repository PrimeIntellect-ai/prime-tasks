venv detection not working with micromamba
- [x] I have searched the issue tracker and believe that this is not a duplicate.

The get_venv_python method on Windows assumes that the Python interpreter in a venv is installed under Scripts below the venv root. With micromamba, it is actually installed directly underneath the venv root.

I’m using micromamba since it’s so much faster than Mamba or Conda.

I think the only workaround at the moment is to explicitly set the saved python using PDM_PYTHON or something like that.

even if this isn’t something the project wishes to address, thought anyone who happened to bump into this might want to know about it.

Motivation: the reason I need to futz with this is that I’m using building multiple platform specific wheels and the default dependency resolution for building is a bit finnicky right now. So making the build command just use a manually specified venv is really nice and micromamba is the fastest one out there.

Thanks for this project, btw. Kinda wish it was just the standard.
