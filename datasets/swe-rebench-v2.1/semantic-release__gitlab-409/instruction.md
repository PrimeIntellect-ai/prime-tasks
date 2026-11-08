asset url containing ${nextRelease.version} not working/expanded
I would like to create version dependent `url`s as release assets pointing to the specific file on an other filehosting server.

```json
["@semantic-release/gitlab", {
      "assets": [
          {"url": "http://fileserver/${nextRelease.version}/update.zip", "label": "update file", "type": "other"}
      ]
}]
```

The release page nevertheless will contain the following link:
```
http://fileserver/$%7BnextRelease.version%7D/update.zip
```

For the asset label that seems to work as the [documentation suggests](https://github.com/semantic-release/gitlab#usage), e.g.
```json
{"path": "dist/asset.min.js", "label": "v${nextRelease.version}.js"}
```

But why not for the `url`?

### Additional contract requirements

- Configured asset `type` and `filepath` values must also support template expressions. When `type` is `${process.env.TYPE}` and `TYPE` is `other`, the release link must have `link_type: "other"`. When `filepath` is `${process.env.FILEPATH}` and `FILEPATH` is `/dist/file.css`, the release link must have `filepath: "/dist/file.css"`.
