Add option for repeat mapping
In `ska map`, having an option to automatically mask any repeats in the reference would be useful. I think converting bases to 'N', if mapped (leaving as gapped otherwise)

### Additional contract requirements

- Expose this option as `--repeat-mask`.
- With `--repeat-mask`, treat a split k-mer as repeated when it occurs more than once anywhere in the reference, including across contigs. For each occurrence, its span is the k-base window centered on the split k-mer's middle position; write `N` at mapped positions in that span and leave unmapped positions gapped.
