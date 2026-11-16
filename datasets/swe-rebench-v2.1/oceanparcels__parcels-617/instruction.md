cannot define variable dt inside kernel
It is currently not possible to define a variable dt inside of a kernel, e.g.:

```
def kernel(particle, fieldset, time):
    dt = particle.dt
    u,v = fieldset.UV[time, particle.depth, particle.lat, particle.lon]
    particle.lon += u * dt

```

changing the name dt to e.g. dtt does work however:
```
def kernel(particle, fieldset, time):
    dtt = particle.dt
    u,v = fieldset.UV[time, particle.depth, particle.lat, particle.lon]
    particle.lon += u * dtt

```
