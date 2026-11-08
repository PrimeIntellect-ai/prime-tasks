Make it easier to go into "debug mode"
What would it take to make it easier to turn debugging messages on (and off) during development?

I think just a helper function would be nice versus manually setting an env var. Maybe it could default to the current package?

~~Then there's also the issue of turning it on, then needing to reload the package. That sounds a bit harder to smooth over, but maybe also possible?~~ *I somehow thought I needed to install/restart/reload, but `load_all()` works, so nevermind.*

### Additional contract requirements

Calling `debugme()` again must apply the current `DEBUGME` setting when deciding whether to instrument the target package, so developers can change the selected packages during a session without reloading the package.
