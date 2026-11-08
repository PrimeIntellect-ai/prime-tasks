Asset static url not quite right
Not sure exactly how to phrase this, but the static url output by `Asset` and `BirdAssetFinder` is not quite right. Here's an example of one, from an application I have running in Docker:

```python
In [26]: x
Out[26]: Asset(path=PosixPath('/app/templates/bird/modal/modal.js'), type=<AssetType.JS: 'js'>)

In [27]: x.relative_path
Out[27]: PosixPath('bird/modal/modal.js')

In [28]: x.absolute_path
Out[28]: PosixPath('/app/templates/bird/modal/modal.js')

In [29]: BirdAssetFinder().find("bird/modal/modal.js")
Out[29]: '/app/templates/bird/modal/modal.js'

In [30]: finders.find("bird/modal/modal.js")
Out[30]: '/app/templates/bird/modal/modal.js'

In [31]: x.url
Out[31]: '/app/templates/bird/modal/modal.js'
```

When used in the `{% bird:js %}` tag, the url is set to the absolute path above instead of being put under the static root.

### Additional contract requirements

- The URL produced for an asset (for example `Asset.url`) must be under the static root: it must begin with Django's configured `STATIC_URL` prefix (for example `/static/`). It must not be the asset's absolute filesystem path.
