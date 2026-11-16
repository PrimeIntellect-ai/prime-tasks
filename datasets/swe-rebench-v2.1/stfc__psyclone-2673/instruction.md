PSyAd to not assume kernel name from module name
Currently PSyAd assumes that the name of the kernel metadata type will be the name of the module with the `_mod` replaced with `_type`. This will not always be the case.

The function `psyclone.domain.lfric.utils.metadata_name_from_module_name()` does this.

It probably needs to be replaced with [HIDDEN].

### Additional contract requirements

- If the supplied PSyIR contains no kernel metadata, `generate_lfric_adjoint()` must raise `InternalError` with a message containing `The supplied PSyIR does not contain any kernel metadata`.
- PSyAd must identify and use the kernel metadata type that extends `kernel_type`, rather than infer its name by replacing the module name’s `_mod` suffix with `_type`.
