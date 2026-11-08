Description of ImagingPlane is required by PyNWB, but not schema
I noticed that `description` is a required property of `ImagingPlane` in PyNWB. In the schema it is listed as optional:

https://github.com/NeurodataWithoutBorders/nwb-schema/blob/5cfe01d428bb432a51f139412fcf60d1a1dfac08/core/nwb.ophys.yaml#L204-L211

This causes an incompatibility between files created by MatNWB, where they can not be read by PyNWB is the ImagingPlane/description is not set.

### Additional contract requirements

- An `ImagingPlane` may be created without a `description`; the description then defaults to `None`.
- The `device`, `excitation_lambda`, `indicator`, and `location` fields remain required: constructing an `ImagingPlane` without any one of them must raise a `ValueError`.
