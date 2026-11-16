Improve `Seeds` command
Currently, the `Seeds` command only returns connected seeds. This is not great, because:

1. If there are no connected seeds, it doesn't give the user the option to connect to an unconnected seed
2. If a seed is connected, but already being fetched from, it's returned anyway

We should return *all* seeds to make that command as useful as possible, but include some kind of "status", which can be either of: `[connected, fetching(rid), disconnected]`.

This will allow the CLI for eg. to make a better choice as to which seed to fetch from.

### Additional contract requirements

- The `radicle::node::Handle` trait's `seeds` method has the signature `fn seeds(&mut self, id: Id) -> Result<Seeds, Self::Error>`, where `Seeds` is `radicle::node::Seeds`.
- `radicle::node::Seeds` exposes these methods, with `NodeId` being `radicle::node::NodeId`:
  - `is_connected(&self, node: &NodeId) -> bool`, which is true when the node is a seed in the connected state.
  - `is_disconnected(&self, node: &NodeId) -> bool`, which is true when the node is a seed in the disconnected state.
  - `is_fetching(&self, node: &NodeId) -> bool`, which is true when the node is a seed currently being fetched from.
