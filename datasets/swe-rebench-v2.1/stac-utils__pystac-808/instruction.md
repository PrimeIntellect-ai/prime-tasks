`Asset.get_absolute_href()` should return `None` but doesn't
When STAC item doesn't have a self link and asset `href` is not absolute then I expect `.get_absolute_href()` to return `None`, instead it returns absolute path in the form `{absolute_path_to_the_current_working_directory}/{relative_path_of_the_asset}`.

```python
from datetime import datetime
import pystac

item = pystac.Item("id", None, None, datetime(2022, 2, 22), {})
item.add_asset("b1", pystac.Asset("b1.tiff"))
assert item.get_self_href() is None
assert item.assets["b1"].get_absolute_href() is None
```

Looking at the code it only returns `None` for "detached" assets.
https://github.com/stac-utils/pystac/blob/2d175d11223738778b54dfd37451134b0c291d44/pystac/asset.py#L102-L103

I think code above should be something along these lines:

```python
[HIDDEN]
```

### Additional contract requirements

- When an asset has a relative HREF and its owning item has no self HREF, `Asset.get_absolute_href()` returns `None`, rather than resolving the HREF against the current working directory.
- When an asset has a relative HREF and its owning item has a self HREF, `Asset.get_absolute_href()` returns the asset HREF resolved against that self HREF.
