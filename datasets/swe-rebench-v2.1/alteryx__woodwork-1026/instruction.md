Handle pd.ExtensionArray inputs into Woodwork
With the DataTables/DataColumns api, we allowed `pd.ExtensionArrays` as inputs so that users wouldn't have to manually convert to a `pd.Series` before creating a DataColumn.

With the Schema/Accessor api, there's no ExtensionArray accessor, so we won't be able to allow creating an initialized column from a ExtensionArray directly. We should determine whether Woodwork should provide a utility function that converts an ExtensionArray to a series object with the accessor already initialized or whether converting from an ExtensionArray to series is left up to the user.

This issue is closely related to #501 and can likely share a common solution. Also, the proposed series creation utility function discussed in #554 could possibly be extended to provide this functionality.

### Additional contract requirements

- `woodwork.accessor_utils.init_series` must accept a pandas `ExtensionArray` directly and return a `pd.Series` with Woodwork typing initialized, without requiring callers to convert the input to a `pd.Series` first.
