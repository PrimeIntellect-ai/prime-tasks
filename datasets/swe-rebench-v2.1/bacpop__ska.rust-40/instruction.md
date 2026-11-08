Add kmer count per sample to ska nk output
There is a really useful QC step with SKA which is to look at the total kmers for each sample. The total kmer numbers should be close to the genome size of the organism to indicate (1) good genome coverage (2) no contamination which will show more kmers, so it's always the first thing we check.

It would be helpful to have that metric for each sample in the current `ska nk` summary output.

Thanks for the new and more powerful implementation!

### Additional contract requirements

The `ska nk` summary written by the `MergeSkaArray` `fmt` implementation must use exactly the following line format, one field per line, in this order:

```
ska_version=<version>
k=<k-mer length>
k_bits=<64 or 128>
rc=<true or false>
k-mers=<total number of split k-mers>
samples=<number of samples>
sample_names=[<comma-separated, double-quoted sample names>]
sample_kmers=[<comma-separated per-sample split k-mer counts>]
```

The total k-mer count, sample count and sample-name list lines are labelled `k-mers=`, `samples=` and `sample_names=` respectively, and the new per-sample counts are written on a `sample_kmers=` line as a Rust-style debug list of integers.
