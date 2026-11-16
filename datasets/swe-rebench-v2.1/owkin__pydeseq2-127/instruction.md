[BUG] deseq2_norm throws KeyError when called on a pandas DataFrame
**Describe the bug**
We are trying to use deseq2_norm to normalized your example data set and our own rna_seq experiment, in both cases the function does not work.

**To Reproduce**
python version = 3.11.3
code :
counts_df = load_example_data(
    modality="raw_counts",
    dataset="synthetic",
    debug=False,
)

deseq2_norm(counts_df)

**Expected behavior**
We were expecting to get a dataframe with the normalized values of the gens in each sample.

**Screenshots**
![image](https://user-images.githubusercontent.com/130982623/235124582-72cd6a37-df72-43e0-8ce4-e7baf53f6679.png)
![image](https://user-images.githubusercontent.com/130982623/235124836-3c2f6e54-45e2-41ee-a170-9243dc0d45b2.png)


**Desktop (please complete the following information):**
 - OS: Linux
 - Version 22.04

**Additional context**
Add any other context about the problem here.

### Additional contract requirements

- The function is `deseq2_norm`, importable from `pydeseq2.preprocessing`.
- It accepts a pandas DataFrame of raw counts with one row per sample and one column per gene.
- It returns a tuple whose first element is a pandas DataFrame of normalized counts with the same samples (rows) and genes (columns) as the input, and whose second element is the one-dimensional per-sample size-factor vector, preserving sample ordering.


- For the same input counts, the size factors returned by `deseq2_norm` must match those produced by `DeseqDataSet.fit_size_factors()` in sample order.
