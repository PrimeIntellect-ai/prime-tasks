Force pushes can lead to "bad object" message from git rev-list
**Describe the bug**
When force-pushing a ref to a remote, if the object the remote side's ref points to is not in the local copy, we'll abort with a message like the following:

```
ref temp:: Error in git rev-list --stdin --objects --not --remotes=origin --: exit status 128 fatal: bad object ae86523521e10b0e8aa3c50dda910064ec2ff155
```

**Expected behavior**
We don't abort in this case and simply skip using that object.

**System environment**
Debian sid, Git LFS `master`

### Additional contract requirements

When a remote-tracking ref points to an object that is absent locally, scanning must succeed and skip that missing object. Other valid local objects in the scan must still be processed.
