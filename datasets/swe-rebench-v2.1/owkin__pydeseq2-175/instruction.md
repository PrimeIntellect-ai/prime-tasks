ValueError: The first guess on the deviance function returned a nan.  This could be a boundary  problem and should be reported.
Hello, thank you for the great tool!

**Describe the bug**
When trying to run the deseq2 method, the following error arises:
`
ValueError: The first guess on the deviance function returned a nan.  This could be a boundary  problem and should be reported.
`
**To Reproduce**
Version: `pydeseq2    0.4.1`
Code:

```
#initialize DeseqDataSet
dds = DeseqDataSet(
    counts = counts,
    metadata=pb.obs,
    design_factors = 'sample')

sc.pp.filter_genes(dds, min_cells = 1) #filter genes that are found in at least one sample

dds.deseq2() #call DESeq2
```
The last line produced the following output in addition to the ValueError:

> Fitting size factors...
> ... done in 0.00 seconds.
>
> /home/jupyter/.local/lib/python3.8/site-packages/pydeseq2/utils.py:1014: RuntimeWarning: divide by zero encountered in divide
>   ((normed_counts - y_hat) ** 2 - y_hat) / ((num_samples - num_vars) * y_hat**2)
> /home/jupyter/.local/lib/python3.8/site-packages/pydeseq2/utils.py:1014: RuntimeWarning: invalid value encountered in divide
>   ((normed_counts - y_hat) ** 2 - y_hat) / ((num_samples - num_vars) * y_hat**2)
> Fitting dispersions...
> ... done in 2.34 seconds.
>
> Fitting dispersion trend curve...
> /opt/conda/envs/NET_py_env/lib/python3.8/site-packages/statsmodels/genmod/families/family.py:177: RuntimeWarning: invalid value encountered in divide
>   return np.sum(resid_dev * freq_weights * var_weights / scale)

How should I proceed?

### Additional contract requirements

- When fitting dispersions, if the design matrix has the same number of rows (samples) as columns (design variables), raise a `ValueError` rather than proceed with a zero-degrees-of-freedom estimate.
