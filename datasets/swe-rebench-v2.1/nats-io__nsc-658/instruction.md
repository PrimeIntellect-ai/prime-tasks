NSC does not allow multiple clusters with 100% weight subject mapping
### What version were you using?

nsc version 2.8.6

### What environment was the server running in?

darwin-arm64

### Is this defect reproducible?

Run the following:
```
nsc add account APP
nsc edit account APP --sk generate
nsc add mapping --account APP --cluster east --from "foo" --to "foo.east" --weight 100
nsc add mapping --account APP --cluster west --from "foo" --to "foo.west" --weight 100
```

### Given the capability you are leveraging, describe your expectation?

That the mapping command would add another element to the mapping slice instead of not allowing it. Trying to do the following with nsc: https://github.com/synadia-labs/eventually-consistent-virtual-global-stream/blob/main/mappings.cfg
But so far no luck

### Given the expectation, what is the defect you are observing?

When the commands run I get the following:
```
$ nsc add mapping --account APP --cluster east --from "foo" --to "foo.east" --weight 100
[ OK ] added mapping foo -> foo.east, weight 100%
$ nsc add mapping --account APP --cluster west --from "foo" --to "foo.west" --weight 100
Error: mapping validation failed: [Mapping "foo" exceeds 100% among all of it's weighted to mappings]
```

### Additional contract requirements

- For an over-100% mapping in cluster `A` from subject `q`, the error must contain `Mapping "q" in cluster "A" exceeds 100%`.
