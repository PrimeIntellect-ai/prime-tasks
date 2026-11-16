Add mass_energy as a new atomic function and a Particle attribute
The nuclear binding energy of a nucleon may be found from the [`nuclear_binding_energy`](https://github.com/PlasmaPy/PlasmaPy/blob/e7912ef7a32487c8193a3f880874b40aa1e4cf7a/plasmapy/atomic/nuclear.py#L18) function of the `atomic` subpackage or with the [`binding_energy`](https://github.com/PlasmaPy/PlasmaPy/blob/e7912ef7a32487c8193a3f880874b40aa1e4cf7a/plasmapy/atomic/particle_class.py#L898) attribute from a [`Particle`](https://github.com/PlasmaPy/PlasmaPy/blob/e7912ef7a32487c8193a3f880874b40aa1e4cf7a/plasmapy/atomic/particle_class.py#L99) instance.  It would be really helpful to have a `mass_energy` function in [`nuclear.py`](https://github.com/PlasmaPy/PlasmaPy/blob/master/plasmapy/atomic/nuclear.py) as well as a `mass_energy` attribute of the Particle class in [`particle_class.py`](https://github.com/PlasmaPy/PlasmaPy/blob/master/plasmapy/atomic/particle_class.py).  [HIDDEN]

Thanks!
-Nick

### Additional contract requirements

- `Particle.mass_energy` returns the particle's mass energy as an `astropy.units.Quantity` in joules. For a nuclide, it represents nuclear mass energy; for other particles and elements, it represents rest-mass energy based on mass times the speed of light squared. If the required mass is unavailable, accessing the attribute raises `MissingAtomicDataError`.
- Provide `plasmapy.atomic.nuclear.mass_energy(particle, mass_numb=None)`, accepting a particle identifier (`str`, `int`, or `Particle`) and an optional isotope mass number. It returns the corresponding mass energy in joules, with the same nuclide and non-nuclide behavior as `Particle.mass_energy`.
