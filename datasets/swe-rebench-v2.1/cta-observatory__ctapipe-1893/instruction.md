Write out `true_image_sum` also when not writing out `true_image`.
**Please describe the use case that requires this feature.**
Currently, the `true_image_sum` is only written when `DataWriter.write_true_images=True`

This is probably the opposite of what we want...


**Describe the solution you'd like**

Write out sum always, full image only when requested.

### Additional contract requirements

- The simulated image table of a DL1 file contains the `true_image_sum` column for every telescope, also when the full `true_image` is not written.
- The full `true_image` column is written only when images are requested to be written.
- Merging DL1 files with `--skip-images` keeps the `true_image_sum` column of the simulated image table and omits the full `true_image` column.
