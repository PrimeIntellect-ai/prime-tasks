Item __geo_interface__ returns the wrong represenation
The Item __geo_interface__ is currently:

```
    @property
    def __geo_interface__(self) -> Optional[Dict[str, Any]]:
        """Returns this item's geometry.

        https://gist.github.com/sgillies/2217756

        Returns:
            Dict[str, Any]: The Item's geometry
        """
        return deepcopy(self.geometry)
```

However, this should be returning a JSON-typed dict of a Feature for the Item, rather than the Item's geometry.
