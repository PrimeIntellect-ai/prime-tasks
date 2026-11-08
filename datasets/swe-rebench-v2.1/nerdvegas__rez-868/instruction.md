add configurability of package orderers
Package orderers as found in package_order.py aren't yet configurable via rezconfig.py. Should support something like:

package_orderers:
- type: soft_timestamp
  package_families: ["maya*"]
  timestamp: 3456789
  rank: 0

### Additional contract requirements

Package ordering can be configured through rezconfig using the documented `per_family` orderer: its `packages` list selects the package families to which a nested orderer applies. A family-scoped `soft_timestamp` orderer must use its configured timestamp and rank, and configured orderers must influence package candidate selection during resolution.
