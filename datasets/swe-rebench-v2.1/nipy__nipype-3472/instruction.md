Add compression to Gunzip interface
In Clinica, we use the [Gunzip](https://github.com/nipy/nipype/blob/6c060304f380c46b2f05c5afdc7171dbbdfadc58/nipype/algorithms/misc.py#L282) interface quite a bit, especially for SPM-based pipelines since SPM does not handle compressed NIfTI files. Afaik, this interface only supports decompression.

Would there be an intereset to enhance this interface to also support compression, so that results from SPM can be persisted in compressed form? Unless there is an alternative option I missed.

### Additional contract requirements

- `Gzip` with `mode="compress"` must write a gzip-compressed copy of `in_file` to `out_file`, so the result can be persisted in compressed form. The output path is derived from `in_file` by appending `.gz` to its extension (for example `sample.nii` becomes `sample.nii.gz`).
- `Gzip` with `mode="decompress"` must write the decompressed contents of `in_file` to `out_file`. When `in_file` ends in `.gz`, the output path drops that suffix (for example `sample.nii.gz` becomes `sample.nii`).
- `Gunzip` must decompress `in_file` to `out_file` using the same naming rule.
