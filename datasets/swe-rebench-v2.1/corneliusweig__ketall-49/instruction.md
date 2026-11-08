Let the user exclude fully-qualified resource kinds
**Is your feature request related to a problem? Please describe.**
Some resource kinds are outputted twice because of the API group changes. For example, `Deployment` is both listed as part of `extensions` and `apps`. I'd like to be able to avoid seeing duplicate resources by excluding the deprecated API group kinds.

**Describe the solution you'd like**
I'd like to be able to explicitly exclude `deployments.extensions` but not `deployments.apps` when using `--exclude`. Right now, one can only `--exclude=deployments` which results in excluding both resource kinds.

**Describe alternatives you've considered**
Right now, I'm filtering out the output using another yaml utility.
