[BUG] EO extension get_bands on a non-EO asset returns Item bands
## Expected Behavior

When using `EOExtension.ext(asset).bands` on an asset that has no bands, it must return `None`.

## Current Behavior

When using `EOExtension.ext(asset).bands` on an asset that has no bands, it may return all Item bands if declared at Item level

## Identified issue

[HIDDEN]

## Possible Solution

[HIDDEN]

## Steps to Reproduce

```python
item = pystac.Item.from_file("https://gist.githubusercontent.com/emmanuelmathot/00e8738216f4a359a42b25ea2ca56271/raw/309ee298080978c692fa729a2ba589f95bfacb1c/S2A_MSIL1C_20200615T060641_N0209_R134_T45WWS_20200615T080720.json")
for key, asset in item.get_assets().items():
    eo_bands = EOExtension.ext(asset).bands
    if (key == "mtd"):
        assert eo_bands is None
```

## Context (Environment)

* python 3.8
* pystac 1.0.0-beta.3

As defined in https://github.com/stac-extensions/eo/:
> The eo:bands array may optionally be used in the Item Properties to summarize the available bands in the assets. This should be a 'union' of all the possible bands represented in assets. It should be considered merely informative - clients should rely on the eo:bands of each asset.
