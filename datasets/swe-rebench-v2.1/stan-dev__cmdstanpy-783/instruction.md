rebuild_cmdstan shouldn't require the existence of the bin/ folder to run
If the build fails for whatever (possibly spurious) reason, running re-build would be fine, except we assert that `bin/stanc` exists already:

https://github.com/stan-dev/cmdstanpy/blob/db3087aed1e2210e51296d403fe3ec710a3bdbbb/cmdstanpy/utils/cmdstan.py#L136-L142

### Additional contract requirements

- Validating a CmdStan installation path must only require the presence of the `makefile`. A CmdStan directory that contains a `makefile` but no `bin/` folder is a valid installation path, so `rebuild_cmdstan` can be attempted on it.
- Add a public function `stanc_path() -> str` in module `cmdstanpy.utils.cmdstan` that returns the absolute path to the `stanc` executable (including the platform-specific extension) of the current CmdStan installation, and raises `ValueError` when that executable is not present in the expected `bin/` directory.
