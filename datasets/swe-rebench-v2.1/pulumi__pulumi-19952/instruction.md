Views: Synthesize delete view steps during `pulumi destroy` previews
We don't currently synthesize delete steps for views during destroy previews. Delete steps are only published for views from the provider's `Delete` rpc, which doesn't run during preview.

This means if a resource has views and you run `pulumi destroy`, the preview will show that the owning resource will be deleted, but it doesn't show a preview of any of its child views.

Worse, if the owning resource is using `RefreshBeforeUpdate`, it will show the views will be refreshed, but it doesn't show that that they will be deleted, which looks confusing, e.g.:

```
$ pulumi destroy
Previewing destroy (dev)

View in Browser (Ctrl+O): ...

     Type                                         Name                                                    Plan        Info
 -   pulumi:pulumi:Stack                          vpcmodtest-dev                                          delete
 -   └─ vpcmod:index:Module                       test-vpc                                                delete
 ~      ├─ vpcmod:tf:aws_route_table_association  module.test-vpc.aws_route_table_association.private[0]  refresh
 ~      ├─ vpcmod:tf:aws_subnet                   module.test-vpc.aws_subnet.public[0]                    refresh
 ~      ├─ vpcmod:tf:aws_subnet                   module.test-vpc.aws_subnet.public[1]                    refresh
 ~      ├─ vpcmod:tf:aws_default_network_acl      module.test-vpc.aws_default_network_acl.this[0]         refresh     [diff: ~egress,ingress]
 ~      ├─ vpcmod:tf:aws_subnet                   module.test-vpc.aws_subnet.private[0]                   refresh
 ~      ├─ vpcmod:tf:aws_route                    module.test-vpc.aws_route.private_nat_gateway[0]        refresh
 ~      ├─ vpcmod:tf:aws_subnet                   module.test-vpc.aws_subnet.private[1]                   refresh
 ~      ├─ vpcmod:tf:aws_default_security_group   module.test-vpc.aws_default_security_group.this[0]      refresh
 ~      ├─ vpcmod:tf:aws_route_table_association  module.test-vpc.aws_route_table_association.public[0]   refresh
 ~      ├─ vpcmod:tf:aws_vpc                      module.test-vpc.aws_vpc.this[0]                         refresh
 ~      ├─ vpcmod:tf:aws_route_table              module.test-vpc.aws_route_table.public[0]               refresh     [diff: ~route]
 ~      ├─ vpcmod:tf:aws_route                    module.test-vpc.aws_route.public_internet_gateway[0]    refresh
 ~      ├─ vpcmod:tf:aws_internet_gateway         module.test-vpc.aws_internet_gateway.this[0]            refresh
 ~      ├─ vpcmod:tf:aws_route_table_association  module.test-vpc.aws_route_table_association.public[1]   refresh
 ~      ├─ vpcmod:tf:aws_route_table_association  module.test-vpc.aws_route_table_association.private[1]  refresh
 ~      ├─ vpcmod:tf:aws_default_route_table      module.test-vpc.aws_default_route_table.default[0]      refresh     [diff: +propagating_vgws]
 ~      ├─ vpcmod:tf:aws_eip                      module.test-vpc.aws_eip.nat[0]                          refresh     [diff: +private_dns~association_id,network_interface
 ~      ├─ vpcmod:tf:aws_nat_gateway              module.test-vpc.aws_nat_gateway.this[0]                 refresh     [diff: +secondary_allocation_ids]
 ~      └─ vpcmod:tf:aws_route_table              module.test-vpc.aws_route_table.private[0]              refresh     [diff: ~route]
```

To fix this, we should synthesize delete view steps during a destroy preview, so that the output shows the child views will be deleted.
