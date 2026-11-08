Adding ${nextRelease.version} to label of asset
Hey not so much an issue as it is a question...

I'm trying to add the nextRelease.version to the label of my asset, but when I do it just comes through as the string for "${nextRelease.version}"

```
[
            "@semantic-release/gitlab",
            {
                "gitlabUrl": "https://example.com",
                "assets": [
                    {"path": "build.tar.gz", "label": "build-v${nextRelease.version}.tar.gz"}
                ]
            }
]
```

**result:**
```
  "assets": {
    "links": [
      {
        "name": "build-v${nextRelease.version}.tar.gz",
        "url": "https://example/path/.../.../build.tar.gz"
      }
    ]
  }
```

**expected:**
```
  "assets": {
    "links": [
      {
        "name": "build-v1.0.0.tar.gz",
        "url": "https://example/path/.../.../build.tar.gz"
      }
    ]
  }
```
I've seen that this feature was added in 6.0.4... so it's more a question of where I'm going wrong 😅 ...
