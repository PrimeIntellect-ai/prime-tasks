Add ability to create NFS Volumes
<!--Please make sure to read the "Reporting Issues" section of the contribution guide before submitting an issue
https://github.com/cdk8s-team/cdk8s/blob/master/CONTRIBUTING.md#reporting-issues
-->

### Description of the feature or enhancement:
NFS Volumes

### Use Case:
I need to mount NFS volumes to my pods. Unfortunately, due to how the `Volume` class is set up, I cannot easily create an NFS volume to pass into the `Deployment` construct.

My current workaround for this is the following:
```
const volume = Volume.fromEmptyDir(this, 'data-volume', 'data-volume', { });
const obj: any = volume as any;
obj.config = {
    nfs: {
        server: '169.254.0.1'
    }
};
```

### Proposed Solution:
 - Add a new static constructor on the `Volume` class to support creating NFS volumes. The underlying `k8s.Volume` already has `nfs` property defined on it.
 - To support other volume types that do not have static constructors defined, I suggest making the `Volume` class constructor public or protected, so that users are left with flexibility to pass in their own configuration objects if they have to.

### Other:
I can help put together a PR if needed

* [X] :wave: I may be able to implement this feature request
* [ ] :warning: This feature might incur a breaking change

---

This is a :rocket: Feature Request

### Additional contract requirements

- Provide the static `Volume.fromNfs(scope, id, name, options)` constructor. The `options` object takes a `server` field (the NFS server hostname or IP) and a `path` field (the exported path on that server). Both values are present in the resulting volume when it is used by a Pod.
