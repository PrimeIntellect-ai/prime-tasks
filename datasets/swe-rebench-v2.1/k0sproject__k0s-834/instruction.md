'k0s validate config' could detect mistyped/unsupported configuration parameters
**Is your feature request related to a problem? Please describe.**

When I mistype a configuration parameter name or value (in k0s.yaml), I don't easily find the problem. For example:
```
installConfig:
  users:
    etcdUserWRONG: etcd
````
or
```
spec:
  api:
    address: 172.WRONG.x.x
    addressWRONG: 172.x.x.x
    sansWRONG:
    - 172.x.x.x
  storageWRONG:
    type: etcd
    etcd:
      peerAddress: 172.x.x.x
  network:
    podCIDR__WRONG: 10.x.0.0/16
````

**Describe the solution you'd like**
'k0s validate config' could help detecting problems like this. Also when starting a controller, the faulty configuration could be detected before actually launching the controller.

### Additional contract requirements

- Configuration validation must detect an invalid API address value and identify the `spec.api.address` field in its error.
- For an API configuration with both an invalid `sans` entry and an invalid `address`, validation must return exactly two separate errors.
- When both an invalid `sans` entry and an invalid `address` are present, the first error's `Error()` string must contain `is not a valid address for sans`.
- The `k0s validate config` workflow must report mistyped or unsupported configuration parameter names to the user instead of silently accepting them.
