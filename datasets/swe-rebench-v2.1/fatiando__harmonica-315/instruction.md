Adding progress bar to forward gravity calculation of prisms
**Description of the desired feature:**
<!--
Add as much detail as you can in your description below. If possible, include an
example of how you would like to use this feature (even better if it's a code
example).
-->
During a call to `prism.gravity` (or `prism_layer.gravity`) it would be great to have a progress bar which updates as the calculations advance through the gravity observation points (`coordinates`) .  @LL-Geo suggested the `numba_progress` package, which seems to be a good fit. Looking through `harmonica.forward.prisms.py`, I assume implementing this feature would be done within the `jit_prism_gravity` function, and when calling the function, users would use something along the lines of:


``` python
with ProgressBar(total=max_iter) as numba_progress:
        topo_prisms.prism_layer.gravity(
               coordinates=(df_grav.x, df_grav.y, df_grav.z),
               field = 'g_z',
               progress=numba_progress)
```


**Are you willing to help implement and maintain this feature?**
<!--
Every feature we add is code that we will have to maintain and keep updated.
Please let us know if you're willing to help maintain this feature in the future.
-->
Yes I'm willing to try, but will likely need some assistance since it's my first code contribution, and I'm unfamiliar with numba_progress.
