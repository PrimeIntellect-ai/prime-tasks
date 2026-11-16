Separate how Particle class treats ions and neutral atoms
Right now the `Particle` class has an attribute `Particle.ion` which returns the ionic symbol if the particle is either an ion or a neutral charged particle (see also #338 which changes `ion_symbol` to `ionic_symbol`).  This can lead to confusion since if we treat `Particle.ion` as a `bool` to check whether or not something is an ion, then it will return `True` for neutral atoms where the charge information is given.

One possibility would be to create an `is_ion` attribute for `Particle` that returns a `bool` of whether or not the particle is a charged ion.  In that case, we could rename `Particle.ion` as `Particle.ionic_symbol` (and `Particle.isotope` as `Particle.isotope_symbol`, etc.) and also create a `Particle.is_isotope` attribute.  We should keep in mind that plasma physicists sometimes worry about electron-positron pair plasmas as we are doing this.

The `categories` and `is_category` attributes of `Particle` need to updated to reflect that `'H 0+'`, for example, is not classified as an `'ion'`.  This would also affect how the `@particle_input` decorator treats things (e.g., the `any_of`, `require`, and `exclude` keyword arguments).

I'm also wondering if the `atomic` subpackage should keep separating elements (e.g., `'H'`, `'He'`, etc.) from neutrally charged atoms (e.g., `'H 0+'`, `'He 0+'`, etc.).  I'm still inclined to keep them separate, since explicitly putting in the charge is better than implicitly assuming it, but this is worth thinking more about too.

### Additional contract requirements

- `Particle.ionic_symbol` is a property that returns the ionic notation string (for example `'D 1+'` or `'H-1 0+'`) for ions and for neutral atoms that have charge information, and returns `None` when the particle does not correspond to an ion or a neutral atom with charge information.
- `Particle.is_ion` is a property that returns `True` when the particle is a charged ion and `False` otherwise, including for neutral atoms that have explicit charge information.
