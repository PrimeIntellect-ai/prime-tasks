Add type hints for creating data/coord field from DataArray class

### Additional contract requirements

Provide the public generic annotation `Coordof[T]` for a coordinate field that refers to a class defining a DataArray, and `Dataof[T]` for a data field that refers to such a class. Each annotation must preserve the referenced class in the field's type information.
