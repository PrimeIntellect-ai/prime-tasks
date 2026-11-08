Remove dependency on goprocess
The dependency on `github.com/jbenet/goprocess` is not needed by boxo. Removing it removes the need to support it in code dependent on boxo, making boxo simpler to use.

### Additional contract requirements

- `github.com/jbenet/goprocess` must no longer be a direct requirement of the
  module: no Go source file in the module may import it (or any of its
  subpackages), and `go.mod` must not list it as a direct dependency. A
  transitive (indirect) requirement is acceptable, since other dependencies may
  still pull it in.
