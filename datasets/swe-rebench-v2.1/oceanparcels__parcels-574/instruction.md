Error in Scipy mode when OutOfBounds in depth dimension.
It seems that in 3D Scipy mode, a particle moving outside of the grid in the depth dimension is not handled correctly, throwing a generic KernelError rather than passing to the recovery kernel as expected.

In the minimal working example below, a 10cell x 10cell x 10cell grid is created, followed by a velocity field with constant flow in the lon and depth directions (and zero flow in the lat direction). I also define a recovery kernel called `DeleteParticle` which simply deletes a particle from its particleset when called.

When a particle `p` crosses the lon limit (i.e. when `p.lon` > 10), it is correctly passed to the recovery kernel and deleted. But when a particle crosses depth limit (`p.depth` > 10), Parcels throws a generic KernelError, rather than calling the recovery kernel.

This issue is not present in JIT mode, where the second particle is deleted as expected.

```
#!/usr/bin/env
from parcels import *

# define recovery kernel
def DeleteParticle(particle, fieldset, time):  # delete particles who run out of bounds.
    print("Particle %d deleted at (%f, %f, %f)" % (particle.id, particle.lon, particle.lat, particle.depth))
    particle.delete()

# create grid
lon = np.linspace(0, 10, 11, dtype=np.float32)
lat = np.linspace(0, 10, 11, dtype=np.float32)
depth = np.linspace(0, 10, 11, dtype=np.float32)
grid = RectilinearZGrid(lon=lon, lat=lat, depth=depth, time=np.zeros(1), mesh='flat')

# create fields
U = Field(name='U', data=np.ones([len(depth), len(lat), len(lon)]), grid=grid,
          allow_time_extrapolation=True)
V = Field(name='V', data=np.zeros([len(depth), len(lat), len(lon)]), grid=grid,
          allow_time_extrapolation=True)
W = Field(name='W', data=np.ones([len(depth), len(lat), len(lon)]), grid=grid,
          allow_time_extrapolation=True)
fieldset = FieldSet(U=U, V=V, fields={'W': W})

# show expected OutOfBounds behaviour when particle crosses lon limit.
particleset_lon = ParticleSet.from_list(fieldset=fieldset, pclass=ScipyParticle,
                                    lon=[9.9],
		                    lat=[5],
		                    depth=[5])
particleset_lon.execute(AdvectionRK4_3D, runtime=1., dt=.5,
                        recovery={ErrorCode.ErrorOutOfBounds: DeleteParticle})

# show erroneous OutOfBounds behaviour when particle crosses depth limit.
particleset_depth = ParticleSet.from_list(fieldset=fieldset, pclass=ScipyParticle,
                                          lon=[5],
		                          lat=[5],
		                          depth=[9.9])
particleset_depth.execute(AdvectionRK4_3D, runtime=1., dt=.25,
                          recovery={ErrorCode.ErrorOutOfBounds: DeleteParticle})
```
