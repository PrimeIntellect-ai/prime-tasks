ingest mounted location into CharmMeta
Obtaining storage location via the storages section,
```python
self.meta.storages["data"].location
```
is not very useful for k8s charms because for k8s charms that sepcifies mount point in the charm container, not the workload.
For the workload, would need something like:
```python
self.meta.containers[self._container_name].mounts[0].location
```
or
```python
self.meta.containers[self._container_name].mounts.data.location
```

However, mounted location is not ingested by CharmMeta
https://github.com/canonical/operator/blob/b1a8fffc053fbbdaf43b826e78c220bfdae4c8fe/ops/charm.py#L891-L892
