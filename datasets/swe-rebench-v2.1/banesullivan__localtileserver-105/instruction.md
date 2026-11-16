could BoundTileLayer be declared outside of the function ?
In one of my application, I'm scrolling in the layers displayed on my map and performed different operations depeding on where there from. The only way I can make the differents between something comming from localtileserver and another TileLayer is the type. In https://github.com/banesullivan/localtileserver/blob/165de5dc63b45689a72e22035f1fa2135eb93b71/localtileserver/widgets.py#L100 you are using the BoundTileLayer for your layer. it's quite hoard to reach for a simple `isinstance` test. would it be possible to set it as a standalone class in `localtileserver.widget` ?

### Additional contract requirements

The standalone class requested above is `LocalTileServerLayerMixin`, defined at module level in `localtileserver.widgets` and importable as `from localtileserver.widgets import LocalTileServerLayerMixin`. It is a marker mixin: the tile layers returned by `get_leaflet_tile_layer` and `get_folium_tile_layer` satisfy `isinstance(layer, LocalTileServerLayerMixin)`. It is also re-exported from the top-level package as `from localtileserver import LocalTileServerLayerMixin`.
