Provide a flag to open data packages with not safe paths?
# Overview

We could allow to open data package with not safe paths if user explicitly choose it:

```python
package = Package(descriptor, safe=False)
```

---

_From @vitorbaptista_

This is what I'm trying to do:

```python
import datapackage

descriptor = {
    'name': 'my-datapackage',
    'resources': [
      {
        'name': 'data',
        'path': '/tmp/my-data.csv'
      }
    ]
}
dp = datapackage.Package(descriptor)
# *** tableschema.exceptions.DataPackageException: Local path "/tmp/my-data.csv" is not safe
```

Reading the `helpers.is_safe_path()` method:

https://github.com/frictionlessdata/datapackage-py/blob/3d25cfd2013c0ddb6b5f9ceb7724dcd111fc9905/datapackage/helpers.py#L189-L196

Makes me think that what I'm trying to do isn't possible anymore. Any known workarounds?

(cc @roll)

### Additional contract requirements

The opt-in flag is named `unsafe`. Opening a package whose resources use paths that are not safe
requires `unsafe=True`, for example `Package(descriptor, unsafe=True)`. The same flag is accepted by
`Resource`, for example `Resource(descriptor, unsafe=True)`.
