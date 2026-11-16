Enable ionization and recombination of Particle objects
There may be occasions where it will be useful to be able to change a `Particle` object representing an ion into a higher or lower charge state.  For example, someone might want to loop through the different charge states of an ion to return something like the ionization energy for each one.

One possibility for the notation would be to create `Particle` class methods called `ionize` and `recombine`:
```Python
>>> from plasmapy.atomic import Particle
>>> deuteron = Particle('D 0+').ionize()
>>> protium = Particle('p+').recombine()
```
These methods would probably be straightforward to implement.

Another possibility would be to use magic methods in the `Particle` class, and enable electrons to be added to or subtracted from ions:
```Python
>>> electron = Particle('e-')
>>> deuteron + electron
Particle('D 0+')
>>> deuteron + 'e-'
Particle('D 0+')
```
This would involve defining the `Particle.__add__` and `Particle.__sub__` magic methods.

I'm not sure how commonly this would be used, so this might be lower priority.  Alternatively, we could use these magic methods for getting nuclear reaction energies (e.g., `Be-8 > 2 * He-4`) also or instead.
