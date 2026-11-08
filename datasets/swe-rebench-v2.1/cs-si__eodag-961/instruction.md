eodag-authenticated and origin raw assets both available in server mode
In server mode, once #721 is done, make available both eodag-authenticated and origin raw assets using https://github.com/stac-extensions/alternate-assets:
```json
{
  "features": [
    {
      "id": "some-product",
      "assets": {
        "B01": {
          "title": "Download link",
          "href": "http://127.0.0.1:5000/collections/some-collection/items/some-product/download/B01",
          "alternate": {
            "origin": {
              "title": "Origin asset link",
              "href": "s3://path/to/B01-asset"
            }
          }
        }
      }
    }
  ]
}
```
