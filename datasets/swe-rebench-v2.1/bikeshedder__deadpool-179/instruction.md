Max & idle connection lifetime
### Discussed in https://github.com/bikeshedder/deadpool/discussions/177

<div type='discussions-op-text'>

<sup>Originally posted by **Sytten** February 11, 2022</sup>
Hi!
I was wondering if you plan to implement maximum and idle lifetimes in the pool? Right now it seems like the checking for bad connections is done lazily at connection fetch. I know for example that sqlx runs a low priority task to check the health of connections in the background and respect the max/idle lifetimes.
Thanks!</div>

### Additional contract requirements

Managed pools must expose a caller-invoked `retain` operation with a predicate that receives each idle pooled object and its metrics. The operation keeps objects for which the predicate returns true and removes objects for which it returns false. Filtering takes effect during the call and is complete when the call returns. Callers may use object state or metrics to apply maximum-lifetime, idle-lifetime, or other policies whenever they invoke the operation; the pool is not required to schedule or enforce expiration automatically in the background.
