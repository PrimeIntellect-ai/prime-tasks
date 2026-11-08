JSON and HDF5 output data not reproducible due to timestamp
Quoting ``table.py``, both methods ``to_json`` and ``to_hdf5`` use the following:

```python
[HIDDEN]
```

Using a live date means otherwise reproducible analysis will fail a simple diff due to the time stamp.

Quoting https://biom-format.org/documentation/format_versions/biom-1.0.html

``date                : <datetime> Date the table was built (ISO 8601 format)``

Quoting https://biom-format.org/documentation/format_versions/biom-2.0.html and https://biom-format.org/documentation/format_versions/biom-2.1.html

``creation-date       : <datetime> Date the table was built (ISO 8601 format)``

In both cases, this is clearly a required field, so I think the best solution is to allow the date to be passed as an optional argument (defaulting to the current default of now). The user could then explicitly use (for example) the last modified date of their input data and metadata. It would also facilitate using diff for continuous integration testing.

In comparison, although the BAM format for sequencing data uses the GZIP header, most implementations deliberately do not fill in the MTIME field, ensuring full reproducibility.

### Additional contract requirements

- `Table.to_hdf5(self, h5grp, generated_by, compress=True, format_fs=None, creation_date=None)` in `biom/table.py`: `creation_date` is an optional `datetime`. When supplied, its ISO-8601 string is stored as the `creation-date` attribute of the HDF5 group; when omitted, the current time is used.
- `Table.to_json(self, generated_by, direct_io=None, creation_date=None)` in `biom/table.py`: `creation_date` is an optional `datetime`. When supplied, its ISO-8601 string is used for the top-level `"date"` field of the JSON output, both when a JSON string is returned and when the output is streamed through `direct_io`; when omitted, the current time is used.
