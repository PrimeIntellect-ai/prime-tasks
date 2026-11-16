[Feature]: Store dimension labels in DatasetBuilder for backends to write
### What would you like to see added to HDMF?

See https://github.com/hdmf-dev/hdmf-zarr/issues/176#issuecomment-2013195105

On write/build, if a data type has dimension labels specified in the spec, then based on the dimensions of the data, we can infer the dimension labels for the data and store those on the DatasetBuilder. The backend (HDF5IO, ZarrIO) can then write the labels however it chooses.

On read/construct, inferring the dimension labels based on the dimensions of the data and the possible options in the spec is a bit trickier because the IO object creates the builders directly and does not have easy access to the spec for the data type. But maybe this is not needed. In the use case described above, it seems like the NWB Zarr files are being read outside of PyNWB.

Adding full support for dimension labels that link across datasets automatically is a bigger feature that requires changes to the schema language and various schema: https://github.com/hdmf-dev/hdmf/pull/192. The effort could be revived but would take a lot longer than the original need.

### What solution would you like?

- Add `dimension_labels` as an attribute on the `DatasetBuilder` (which may be None of the labels are unknown) [hdmf-dev/hdmf@5c85062/src/hdmf/build/builders.py#L321](https://github.com/hdmf-dev/hdmf/blob/5c8506216995f995b891da1e6b596ee42b7dd948/src/hdmf/build/builders.py#L321)
- Enhance `BuildManger.build` to set the `dimension_labels` for `DatasetBuilders` [hdmf-dev/hdmf@5c85062/src/hdmf/build/manager.py#L148](https://github.com/hdmf-dev/hdmf/blob/5c8506216995f995b891da1e6b596ee42b7dd948/src/hdmf/build/manager.py#L148)

### Do you have any interest in helping implement the feature?

Yes.

### Additional contract requirements

- When multiple allowed shapes match, use the labels for the more specific matching shape. For data shape `(2, 3)`, if `[None, None]` has labels `['a', 'b1']` and `[None, 3]` has labels `['a', 'b2']`, `dimension_labels` must be `('a', 'b2')`.

- `DatasetBuilder` (in `hdmf.build.builders`) exposes a public `dimension_labels` property that returns the stored tuple of dimension-label strings, or `None` when the labels are unavailable.
- `IncorrectDatasetShapeBuildWarning` is a public warning class in `hdmf.build.warnings` that subclasses `BuildWarning`.
- When the shape of a dataset's data does not match the single shape allowed by its spec, an `IncorrectDatasetShapeBuildWarning` is emitted with the message `Shape of data does not match shape in spec '<spec_path>'`, where `<spec_path>` is the path of the dataset spec.
- When the shape of a dataset's data matches none of the multiple shapes allowed by its spec, an `IncorrectDatasetShapeBuildWarning` is emitted with the message `Shape of data does not match any allowed shapes in spec '<spec_path>'`, where `<spec_path>` is the path of the dataset spec.
