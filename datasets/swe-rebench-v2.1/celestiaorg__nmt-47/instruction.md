Change NMT Leaf Node to Hash the NID
Implementation for the Namespaced Merkle Tree (NMT) leaf node must be changed to hash the Namespace ID.  In the new implementation, leaf node 'node' of share data d should be structured as follows:

node.n_min = d.namespaceID
node.n_max = d.namespaceID
node.v = h(0x00, d.namespaceID, d.rawData)

See [PR #203](https://github.com/celestiaorg/celestia-specs/pull/203) opened for celestia-specs for the current structure of the NMT leaf node.
