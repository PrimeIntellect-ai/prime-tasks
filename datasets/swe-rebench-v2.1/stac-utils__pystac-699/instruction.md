`DatacubeExtension.variables` doesn't have a setter
There's no `variables.setter` defined at https://github.com/stac-utils/pystac/blob/6e6e987dcb0e711adcd89432bd495199923cf759/pystac/extensions/datacube.py#L548.

I think there should be one, analogous to https://github.com/stac-utils/pystac/blob/6e6e987dcb0e711adcd89432bd495199923cf759/pystac/extensions/datacube.py#L543-L545.

### Additional contract requirements

- In module `pystac.extensions.datacube`, the class `Variable` provides a
  `from_dict(d: Dict[str, Any]) -> Variable` constructor that builds a `Variable`
  representing the provided definition, and a `to_dict(self) -> Dict[str, Any]`
  method that returns the variable's properties as a plain dictionary.
- `DatacubeExtension.variables` is a property whose getter returns
  `Optional[Dict[str, Variable]]`: a mapping from variable names to `Variable`
  objects, or `None` when the `cube:variables` property is absent.
- The `DatacubeExtension.variables` setter accepts an
  `Optional[Dict[str, Variable]]` mapping from variable names to `Variable`
  objects, converting each `Variable` to its dictionary form. Assigning `None`
  clears the `cube:variables` property so that the getter subsequently returns
  `None`.
