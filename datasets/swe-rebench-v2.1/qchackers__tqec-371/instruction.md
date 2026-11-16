Add a `name` field to `Plaquette`
**Is your feature request related to a problem? Please describe.**
#350 requires to be able to hash `Plaquettes` instances, which in turn requires `Plaquette` instances to be hashable. Right now, the hash is not really robust: it is hashing the string representation of the underlying `stim.Circuit` instance, that **should** never be mutated, but that is not strictly enforced (we just cannot replace the `Plaquette.circuit` field, which does not mean that we cannot mutate the `circuit` field with mutating methods from `ScheduledCircuit`).

Moreover, another issue I had recently is my inability to display nicely `Plaquettes` instances when trying to debug the code.

**Describe the solution you'd like**
Adding a unique and descriptive name to `Plaquette` instances (that should be made immutable in a more robust way, #358 goes in this direction) would solve the 2 issues above:

1. hashing a `Plaquette` instance would just be hashing its name, which is nice because this is a constant (and quick) operation.
2. debugging will be nicer as I will be able to print `Plaquettes` instances and have a readable output (e.g., `{1: "XX_up", 3: "ZZZZ", default: "XXXX"}`).

### Additional contract requirements

- `Plaquette` (in `tqec.plaquette.plaquette`) has a public `name` attribute of type `str`, provided as the first argument of its constructor: `Plaquette(name: str, qubits: PlaquetteQubits, circuit: ScheduledCircuit, mergeable_instructions: frozenset[str] = frozenset())`.
- Two `Plaquette` instances compare equal if and only if their `name` values are equal, and a `Plaquette`'s hash is derived solely from its `name`.
- `str(plaquette)` returns the plaquette's `name`.
- `make_css_surface_code_plaquette` (in `tqec.plaquette.library.css`) produces the following names:
  - basis `X` with default options: `CSS_basis(X)_VERTICAL`
  - basis `Z` with default options: `CSS_basis(Z)_VERTICAL`
  - basis `X` with horizontal x-boundary orientation: `CSS_basis(X)_HORIZONTAL`
  - basis `Z` with horizontal x-boundary orientation: `CSS_basis(Z)_HORIZONTAL`
  - basis `Z` with data initialization and measurement in `Z`: `CSS_basis(Z)_VERTICAL_datainit(Z)_datameas(Z)`
  - basis `X` with data initialization and measurement in `X`: `CSS_basis(X)_VERTICAL_datainit(X)_datameas(X)`
  - basis `X` with initialization in `X` only on `RIGHT`: `CSS_basis(X)_VERTICAL_datainit(X,RIGHT)`
  - basis `Z` with measurement in `Z` only on `UP`: `CSS_basis(Z)_VERTICAL_datameas(Z,UP)`
  - projecting the default basis-`X` vertical plaquette on `UP`, `DOWN`, `LEFT`, `RIGHT`: `CSS_basis(X)_VERTICAL_UP`, `CSS_basis(X)_VERTICAL_DOWN`, `CSS_basis(X)_VERTICAL_LEFT`, `CSS_basis(X)_VERTICAL_RIGHT`
- `make_zxxz_surface_code_plaquette` (in `tqec.plaquette.library.zxxz`) produces the following names:
  - basis `X` with default options: `ZXXZ_basis(X)_VERTICAL`
  - basis `Z` with default options: `ZXXZ_basis(Z)_VERTICAL`
  - basis `X` with horizontal x-boundary orientation: `ZXXZ_basis(X)_HORIZONTAL`
  - basis `Z` with data initialization and measurement in `Z`: `ZXXZ_basis(Z)_VERTICAL_datainit(Z)_datameas(Z)`
  - basis `X` with data initialization and measurement in `X`: `ZXXZ_basis(X)_VERTICAL_datainit(X)_datameas(X)`
  - basis `Z` with horizontal x-boundary orientation and initialization and measurement in `Z` only on `RIGHT`: `ZXXZ_basis(Z)_HORIZONTAL_datainit(Z,RIGHT)_datameas(Z,RIGHT)`
  - basis `X` with initialization in `X` only on `RIGHT`: `ZXXZ_basis(X)_VERTICAL_datainit(X,RIGHT)`
  - basis `Z` with measurement in `Z` only on `UP`: `ZXXZ_basis(Z)_VERTICAL_datameas(Z,UP)`
  - projecting the basis-`X` vertical plaquette with initialization and measurement in `X` on `UP`, `DOWN`, `LEFT`, `RIGHT`: `ZXXZ_basis(X)_VERTICAL_datainit(X)_datameas(X)_UP`, `ZXXZ_basis(X)_VERTICAL_datainit(X)_datameas(X)_DOWN`, `ZXXZ_basis(X)_VERTICAL_datainit(X)_datameas(X)_LEFT`, `ZXXZ_basis(X)_VERTICAL_datainit(X)_datameas(X)_RIGHT`
