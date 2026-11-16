Support `hb_format` for multiformat AMP requests
Prebid.js supports `hb_format` to enable multiformat imps on AMP, see [multi-format](http://prebid.org/adops/setting-up-prebid-multi-format-in-dfp.html). The spec itself already exists in the prebid.js documentation, we just need to implement this on PBS.

In line with other flags we have on key value generation, I propose we add an `includeformat` flag to the `targeting` extension. So the targeting API would look like:
```
{
  "ext": {
    "prebid": {
      "targeting": {
        "pricegranularity": {
          "precision": 2,
          "ranges": [{
            "max": 20.00,
            "increment": 0.10 // This is equivalent to the deprecated "pricegranularity": "medium"
          }]
        },
        "includewinners": false, // Optional param defaulting to true
        "includebidderkeys": false // Optional param defaulting to true
        "includeformat": false //Optional param defaulting to false
      }
    }
  }
}
```
Thus all current requests would not get `hb_format` added to the key values, but requests that need it can add the flag in order to get access to this value.
