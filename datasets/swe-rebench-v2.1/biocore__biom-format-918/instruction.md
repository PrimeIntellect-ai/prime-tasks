Misleading behaviour with biom validate and classic TSV input
I do understand that what you call a TSV-formatted (classic) table is *not* considered to be a BIOM format file, but the behaviour of ``biom validate-table`` given such a file is not ideal.

I would like the validate-table help to be explicit about this:

```
$ biom validate-table -h
Usage: biom validate-table [OPTIONS]

  Validate a BIOM-formatted file.

  Test a file for adherence to the Biological Observation Matrix (BIOM) format
  specification. This specification is defined at http://biom-format.org

  Example usage:

  Validate the contents of table.biom for adherence to the BIOM format
  specification

  $ biom validate-table -i table.biom

Options:
  -i, --input-fp FILE        The input filpath to validate against the BIOM
                             format specification  [required]
  -f, --format-version TEXT  The specific format version to validate against
  -h, --help                 Show this message and exit.
```

# Example of current behaviour:

```
$ biom --version
biom, version 2.1.14
$ biom convert -i min_sparse_otu_table_hdf5.biom -o min_sparse_otu_table.tsv --to-tsv
$ biom validate-table -i min_sparse_otu_table_hdf5.biom
$ biom validate-table -i min_sparse_otu_table.tsv
Traceback (most recent call last):
...
json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)
```

# Expected behaviour:

Clear error message like "This file is not in HDF5 or JSON format" or better "This is a TSV file, not a BIOM file." (*edited to fix missing pronouns*)
