rolling-update does not validate cluster correctly after bastion
I am using 1.17.0-alpha.1 in openstack and see following:

```
kops rolling-update cluster --instance-group bastions,master-zone-1-1,master-zone-2-1,master-zone-3-1,nodes-z1,nodes-z2,nodes-z3 --validation-timeout 20m --yes

NAME		STATUS		NEEDUPDATE	READY	MIN	MAX	NODES
bastions	NeedsUpdate	1		0	1	1	0
master-zone-1-1	NeedsUpdate	1		0	1	1	1
master-zone-2-1	NeedsUpdate	1		0	1	1	1
master-zone-3-1	NeedsUpdate	1		0	1	1	1
nodes-z1	NeedsUpdate	2		0	2	2	2
nodes-z2	NeedsUpdate	2		0	2	2	2
nodes-z3	NeedsUpdate	1		0	1	1	1
I1209 12:52:50.771059      96 instancegroups.go:304] Stopping instance "7da46c57-0315-4f53-92df-1966a7c32fc7", in group "cortex-poc.k8s.local-bastions" (this may take a while).
W1209 12:52:50.771124      96 instance.go:105] This does not work without running kops update cluster --yes in another terminal
I1209 12:52:51.900333      96 instancegroups.go:189] waiting for 15s after terminating instance
I1209 12:53:06.901075      96 instancegroups.go:193] Deleted a bastion instance, 7da46c57-0315-4f53-92df-1966a7c32fc7, and continuing with rolling-update.
master not healthy after update, stopping rolling-update: "cluster \"cortex-poc.k8s.local\" did not pass validation: InstanceGroup \"bastions\" did not have enough nodes 0 vs 1"
I1209 12:53:13.534549       1 batch.go:835] error running kops rolling-update cluster --instance-group bastions,master-zone-1-1,master-zone-2-1,master-zone-3-1,nodes-z1,nodes-z2,nodes-z3 --validation-timeout 20m --yes
error running: exit status 1
```

So the kops is waiting 15 seconds to get bastion instance back, and because none autoscaler can handle that. The code will fail. Temporary fix to this is insert `--bastion-timeout=2m`. However, I think this retry logic should be fixed in kops. We need to retry validation also after bastion until validation-timeout.
