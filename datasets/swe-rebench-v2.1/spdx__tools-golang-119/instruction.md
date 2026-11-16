builder: Missing mandatory field LicenseInfoInFile
SPDX Documents created by `builder` appear to be missing the mandatory field `LicenseInfoInFile` for each File section that the builder creates.

This appears to be the combination of:
* in `builder`, [`BuildFileSection2_2`](https://github.com/spdx/tools-golang/blob/4250e11a6f1fac2967008d51f5170630f1f75faa/builder/builder2v2/build_file.go#L50) (and 2_1) [HIDDEN]; and
* in `tvsaver`, [`renderFile2_2`](https://github.com/spdx/tools-golang/blob/4250e11a6f1fac2967008d51f5170630f1f75faa/tvsaver/saver2v2/save_file.go#L35) (and 2_1) [HIDDEN].

[HIDDEN]

Note that SPDX 2.3 will likely permit the omission of the licensing and copyright fields (to be deemed equivalent to NOASSERTION if absent), so this can likely be reverted for 2.3. But given these fields being mandatory for 2.1 and 2.2, it should be present.

### Additional contract requirements

- For SPDX 2.1 and 2.2, each file section created by the builder when no license information is available must have exactly one `LicenseInfoInFile` entry: `NOASSERTION`.
