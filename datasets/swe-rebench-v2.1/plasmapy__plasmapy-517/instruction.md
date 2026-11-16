Have Particle class return corresponding Particle instance for Particle arguments
I've run into a bunch of situations where I have some objects that are either `Particle` class instances or `str`/`int` representations of particles, and I want to make sure that they are all `Particle` class instances.  I have usually written code like this:
```Python
>>> orig_particles = ['H', Particle('He')]
>>> particles = [
        particle if isinstance(particle, Particle) else Particle(particle)
        for particle in orig_particles
    ]
```
This code is rather obfuscating since it checks on whether or not `particle` is a `Particle` class instance.  It would be simpler to have `Particle` return the corresponding `Particle` instance which would allow code like this:
```Python
>>> particles = [Particle(particle) for particle in particles]
```
@StanczakDominik suggested that this be a copy of the `Particle` instance rather than returning self, which is like how `numpy.array` behaves.

A good test would be to check that `Particle(something) == Particle(Particle(something))`, e.g., something like:
```Python
from plasmapy.atomic import Particle
def test_particle_of_particle(particle_representation):
    particle = Particle(particle_representation)
    particle_of_particle = Particle(particle)
    assert particle == particle_of_particle
    assert particle is not particle_of_particle  # to make sure it is a copy rather than self
```
Thanks!
-Nick
