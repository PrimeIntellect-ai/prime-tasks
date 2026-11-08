Update to flosch/pongo2.v4?
Currently distrobuilder depends on both `github.com/flosch/pongo2` and `gopkg.in/flosch/pongo2.v3`. Is there a particular reason why there are two different versions of this library being used? Selfishly asking with my packager hat on, could distrobuilder update to `flosch/pongo2.v4`? I know it's not the most current version of that library, but it is already packaged in Debian. :grinning:

### Additional contract requirements

The migration to `github.com/flosch/pongo2/v4` applies to the whole module, not just a single package. Every package in the module must import `github.com/flosch/pongo2/v4` instead of the legacy `github.com/flosch/pongo2` and `gopkg.in/flosch/pongo2.v3` import paths, and the module must resolve `github.com/flosch/pongo2/v4` as a dependency.
