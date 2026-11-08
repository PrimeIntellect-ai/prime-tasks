extra_cluster_params should merge dictionaries
Currently, if you do something like this in your config:

```
runners:
  emr:
    extra_cluster_params:
      Instances:
        EmrManagedMasterSecurityGroup: sg-00000000000000000
```

it'll actually blow away the entire `Instances` parameter to `RunJobFlow`, rather than just setting the security group. This is almost certainly not what users expect.
