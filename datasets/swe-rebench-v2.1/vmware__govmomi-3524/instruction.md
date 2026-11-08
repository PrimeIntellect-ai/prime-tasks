[BUG] DatacentersFolders.VmFolder is not a complete path when datacenter is in a datacenter folder.
**Describe the bug**

DatacentersFolders.VmFolder is not a complete path when datacenter is in a datacenter folder.

using this snipit and output as the example

```
	dc, err := finder.Datacenter(ctx, failureDomain.Topology.Datacenter)
        if err != nil {
                return err
        }

        dcFolders, err := dc.Folders(ctx)
        if err != nil {
                return fmt.Errorf("unable to get datacenter folder: %w", err)
        }


        logrus.Debugf("datacenter inventory path: %s", dc.InventoryPath)

        logrus.Debugf("datacenter vm folder inventory path: %s\n", folderPath)

```
output
```
DEBUG datacenter inventory path: /dcfolder/dcfolder1/dcfolder2/nested8-datacenter
DEBUG datacenter vm folder inventory path: /nested8-datacenter/vm/jcallen3-rlr9v
```


**To Reproduce**
Steps to reproduce the behavior:

1. always, see above

**Expected behavior**

The DatacenterFolders.VmFolder is the full complete path to `/vm`
(for our example that is `/dcfolder/dcfolder1/dcfolder2/nested8-datacenter/vm`)

**Affected version**
github.com/vmware/govmomi v0.37.2

### Additional contract requirements

- When a datacenter has inventory path `/F0/DC1`, each of `DatastoreFolder`, `HostFolder`, `NetworkFolder`, and `VmFolder` must have an `InventoryPath` equal to `/F0/DC1/` followed by that folder's name.
