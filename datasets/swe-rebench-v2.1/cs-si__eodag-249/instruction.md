Default behaviour for extracting products
I've just used `eodag-sentinelsat` and was surprised to see I had to set the `extract` parameter to a value (True or False). Before that, I never set this value and it seems to me that products were always extracted.

Currently in providers.yml:
* usgs: true
* aws_eos: (irrelevant as AWS download)
* theia: true
* peps: true
* sobloo: true
* creodias: true
* mundi: true
* (wekeo): broken now
* onda: true
* astraea_eod: (irrelevant as AWS download)
* usgs_satapi_aws: (irrelevant as AWS download)
* earth_search: (irrelevant as AWS download)
* earth_search_cog: (irrelevant as COG)

[HIDDEN]
https://github.com/CS-SI/eodag/blob/0632e4147f26119bea43e0672f6d06e75d216a20/eodag/plugins/download/base.py#L151-L161

[HIDDEN]

The template indicates:
```
            extract:  # whether to extract the downloaded products (true or false).
```

Should we:

* Specify that the default behavior is to automatically extract products?
* Update `_finalize` accordingly?
* Indicate to plugin developers that they should extract automatically by default?
* Update eodag-sentinelsat accordingly?

### Additional contract requirements

- When `extract` is not supplied for a download and is not set in the provider configuration, extractable products should be extracted by default.
