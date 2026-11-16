New pickling methods loads all absolute links
Since the PR https://github.com/stac-utils/pystac/pull/1285 and more specifically this [change](https://github.com/stac-utils/pystac/pull/1285/files#diff-c235f14269d2641c490a6ec16abb7ab96c1f7d4e2ca4514b0ade666b2094469eR179), it seems that a deepcopy of an item will load all the links with an absolute href.
Is it intended or am I missing something?
This causes issue when loading assets using `get_assets` method that makes first a deep copy of the stac object that uses pickling.
When I load an item with unreachable links (e.g. s3 url but no custom IO reader set) and try to list the assets, it raises an issue.

```rio_tiler/io/stac.py:258: in __attrs_post_init__
    self.assets = list(
rio_tiler/io/stac.py:149: in _get_assets
    for asset, asset_info in stac_item.get_assets().items():
venv/lib/python3.11/site-packages/pystac/asset.py:300: in get_assets
    return {
venv/lib/python3.11/site-packages/pystac/asset.py:301: in <dictcomp>
    k: deepcopy(v)
/usr/lib/python3.11/copy.py:172: in deepcopy
    y = _reconstruct(x, memo, *rv)
/usr/lib/python3.11/copy.py:271: in _reconstruct
    state = deepcopy(state, memo)
/usr/lib/python3.11/copy.py:146: in deepcopy
    y = copier(x, memo)
/usr/lib/python3.11/copy.py:231: in _deepcopy_dict
    y[deepcopy(key, memo)] = deepcopy(value, memo)
/usr/lib/python3.11/copy.py:161: in deepcopy
    rv = reductor(4)
venv/lib/python3.11/site-packages/pystac/item.py:179: in __getstate__
    d["links"] = [
[HIDDEN]
/usr/lib/python3.11/urllib/request.py:216: in urlopen
    return opener.open(url, data, timeout)
/usr/lib/python3.11/urllib/request.py:519: in open
    response = self._open(req, data)
/usr/lib/python3.11/urllib/request.py:541: in _open
    return self._call_chain(self.handle_open, 'unknown',
/usr/lib/python3.11/urllib/request.py:496: in _call_chain
    result = func(*args)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <urllib.request.UnknownHandler object at 0x74a76915ba50>
req = <urllib.request.Request object at 0x74a768cd8dd0>

    def unknown_open(self, req):
        type = req.type
>       raise URLError('unknown url type: %s' % type)
E       urllib.error.URLError: <urlopen error unknown url type: s3>
```

### Additional contract requirements

- Deep-copying a STAC Item, including when performed by `get_assets`, must not load or resolve its absolute links. An unreachable absolute link must not cause deep-copying or asset listing to fail.
