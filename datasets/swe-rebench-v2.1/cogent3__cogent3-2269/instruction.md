new_type Alignment
**Describe the bug**
after renaming sequences, then calling omit_gap_pos(), get a key error

```
aln = cogent3.load_aligned_seqs("~/repos/Cogent3/tests/data/brca1.fasta", moltype="dna", new_type=True)
aln = aln.rename_seqs(lambda x: x.lower())
aln = aln.take_seqs(["human", "chimpanzee", "gorilla", "orangutan", "rhesus"])
aln.omit_gap_pos()
```
