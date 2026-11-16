Add --wait flag to load-balancer create command
**What is the problem this feature would solve? Please describe.**

`doctl` aims to be useful in scripting. One way it does this is by providing a `--wait` flag for long running, async operations to block until until they are complete rather than making the user implement polling in their own script. Some examples include:

- `doctl compute droplet create --wait`
- `doctl kubernetes cluster create --wait`
- `doctl apps create --wait`

Currently the `doctl compute load-balancer create` command does not have a `--wait` flag.

**Describe the solution you'd like**

Add a `--wait` flag to the `doctl compute load-balancer create` command. It should poll the [`/v2/load_balancers/$LOAD_BALANCER_ID` endpoint](https://docs.digitalocean.com/reference/api/api-reference/#operation/loadBalancers_get), blocking until the load balancer's `status` attribute moves from `new` to `active`.

**Additional context**

Following the code path starting here demonstrates how `doctl apps create`'s  `--wait` flag is implemented:

https://github.com/digitalocean/doctl/blob/de1918ad1ee4b1e523c335fa9254e85d415d18aa/commands/apps.go#L282

### Additional contract requirements

- On successful creation, print `Notice: Load balancer created`. When `--wait` is supplied, also print `Notice: Load balancer creation is in progress, waiting for load balancer to become active` before the created notice.
- After successful creation, also display the created load balancer in the standard table output, including its ID.
