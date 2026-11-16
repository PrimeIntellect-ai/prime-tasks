Lower bounding fleet sizes with reloading
Currently, `minimise_fleet` uses demand to estimate a lower bound on the number of needed vehicles:

https://github.com/PyVRP/PyVRP/blob/68d07577540431fe6a6fb26117e7598fcc270226/pyvrp/minimise_fleet.py#L95-L106

This is fine when vehicles are only allowed to execute a single trip. Now, with multiple trips, this relation no longer holds. How do we handle that?

The easiest is probably to [HIDDEN]. `max_trips` is already 1 in case reloading is not possible. The downside is that we do not get a very informative lower bound for multi-trip instances, but that should be OK.

### Additional contract requirements

- The demand-based lower bound in fleet minimisation must account for the vehicle's permitted trips when estimating how many vehicles are needed.
