Appending to Tagged VLANs is not Idempotent
Appending a VLAN object ID to `tagged_vlans` that's already present causes save() to still send a patch.
