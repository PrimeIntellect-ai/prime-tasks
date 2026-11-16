Remove the distance field from CH shortcuts
Removing `dist` from the CH shortcuts saves some memory (10% per shortcut). Right now we do not really use the distances stored in the shortcuts anyway. For example during path calculation we already calculate the distance from the original edge distances.

### Additional contract requirements

CH shortcut storage must omit the distance field and reduce storage by four bytes per shortcut: a node-based shortcut occupies 28 bytes and an edge-based shortcut occupies 36 bytes.

The CH graph methods that create shortcuts no longer take a distance argument. A node-based shortcut is created by `CHGraph.shortcut(a, b, accessFlags, weight, skippedEdge1, skippedEdge2)`, and an edge-based shortcut by `CHGraph.shortcutEdgeBased(a, b, accessFlags, weight, skippedEdge1, skippedEdge2, origFirst, origLast)`. Both return the id of the new shortcut edge.
