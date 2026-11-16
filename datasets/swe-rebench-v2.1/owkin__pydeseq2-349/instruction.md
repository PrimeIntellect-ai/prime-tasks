[BUG] lfc_shrink() generates wrong results
**Describe the bug**
lfc_shrink() generates wrong results. In most cases it acts as expected. For some genes it increases absolute value of fold change. For one differentially expressed gene with high expression (base_mean = 407277.128029) it even changes the sign (
log2FoldChange = -0.753026; shrankLog2FoldChange = 1.844100).

**To Reproduce**
```
import pandas as pd
import seaborn as sns
import matplotlib.pyplot as plt

from pydeseq2.dds import DeseqDataSet
from pydeseq2.default_inference import DefaultInference
from pydeseq2.ds import DeseqStats

inference = DefaultInference(n_cpus=32)

dds = DeseqDataSet(
    counts=counts_df,
    metadata=metadata_df,
    design_factors='condition',
    inference=inference,
)
dds.deseq2()

stat_res = DeseqStats(
    dds,
    contrast=['condition', 'B', 'A'],
    inference=inference
)
stat_res.summary()
stat_res_df = stat_res.results_df.copy()

stat_res.lfc_shrink('condition_B_vs_A')
stat_res_shrinked_df = stat_res.results_df.copy()
stat_res_shrinked_df = stat_res_shrinked_df.rename(columns={'log2FoldChange': 'log2FoldChange_shrank'})

merged_df = pd.merge(stat_res_df, stat_res_shrinked_df, left_index=True, right_index=True)
merged_df = merged_df[(merged_df['padj_x'].notna())]

sns.scatterplot(
    merged_df,
    x='log2FoldChange',
    y='log2FoldChange_shrank'
)

# replace the sns.scatterplot() with code below to get rid of seaborn dependency
# plt.scatter(
#     x=merged_df['log2FoldChange'],
#     y=merged_df['log2FoldChange_shrank']
#)

plt.axline((0, 0), (1,1))
```
```
Fitting size factors...
... done in 0.02 seconds.

Fitting dispersions...
... done in 1.83 seconds.

Fitting dispersion trend curve...
... done in 0.55 seconds.

Fitting MAP dispersions...
... done in 1.79 seconds.

Fitting LFCs...
... done in 2.18 seconds.

Calculating cook's distance...
... done in 0.02 seconds.

Replacing 0 outlier genes.

Running Wald tests...
... done in 2.47 seconds.

Fitting MAP LFCs...
Log2 fold change & Wald test p-value: condition B vs A
                       baseMean  log2FoldChange     lfcSE      stat    pvalue  \
GENEID
ENSG00000000003.15  6312.552040       -0.406453  0.092641 -4.387384  0.000011
ENSG00000000005.6      5.337949       -5.852983  2.030001 -2.883242  0.003936
ENSG00000000419.14  3926.067459        0.396839  0.089676  4.425236  0.000010
ENSG00000000457.14   986.626013       -0.033945  0.132989 -0.255247  0.798532
ENSG00000000460.17  3054.441682       -0.008417  0.079740 -0.105558  0.915933
...                         ...             ...       ...       ...       ...
ENSG00000289714.1      0.000000             NaN       NaN       NaN       NaN
ENSG00000289715.1      0.000000             NaN       NaN       NaN       NaN
ENSG00000289716.1     55.728811        1.269762  0.336892  3.769053  0.000164
ENSG00000289718.1      0.000000             NaN       NaN       NaN       NaN
ENSG00000289719.1     11.956688        2.075506  0.837589  2.477953  0.013214

                        padj
GENEID
ENSG00000000003.15  0.000048
ENSG00000000005.6   0.010336
ENSG00000000419.14  0.000041
ENSG00000000457.14  0.863010
ENSG00000000460.17  0.944234
...                      ...
ENSG00000289714.1        NaN
ENSG00000289715.1        NaN
ENSG00000289716.1   0.000564
ENSG00000289718.1        NaN
ENSG00000289719.1   0.030276

[61125 rows x 6 columns]
/home/.../pydeseq2/utils.py:1260: RuntimeWarning: overflow encountered in exp
  counts - (counts + size) / (1 + size * np.exp(-xbeta - offset))

Shrunk log2 fold change & Wald test p-value: condition B vs A
                       baseMean  log2FoldChange     lfcSE      stat    pvalue  \
GENEID
ENSG00000000003.15  6312.552040       -0.405783  0.092409 -4.387384  0.000011
ENSG00000000005.6      5.337949       -6.123571  2.817030 -2.883242  0.003936
ENSG00000000419.14  3926.067459        0.387581  0.089467  4.425236  0.000010
ENSG00000000457.14   986.626013       -0.035274  0.131941 -0.255247  0.798532
ENSG00000000460.17  3054.441682       -0.007822  0.079505 -0.105558  0.915933
...                         ...             ...       ...       ...       ...
ENSG00000289714.1      0.000000             NaN       NaN       NaN       NaN
ENSG00000289715.1      0.000000             NaN       NaN       NaN       NaN
ENSG00000289716.1     55.728811        1.162090  0.337499  3.769053  0.000164
ENSG00000289718.1      0.000000             NaN       NaN       NaN       NaN
ENSG00000289719.1     11.956688        1.440262  0.866340  2.477953  0.013214

                        padj
GENEID
ENSG00000000003.15  0.000048
ENSG00000000005.6   0.010336
ENSG00000000419.14  0.000041
ENSG00000000457.14  0.863010
ENSG00000000460.17  0.944234
...                      ...
ENSG00000289714.1        NaN
ENSG00000289715.1        NaN
ENSG00000289716.1   0.000564
ENSG00000289718.1        NaN
ENSG00000289719.1   0.030276

[61125 rows x 6 columns]
... done in 1.97 seconds.
```

**Expected behavior**
No increase in absolute value of fold change (if i understand correctly what apeGLM shrinking is doing).
No change in direction of fold change in very abundant differentially expressed genes.
No instability based on the name of conditions.

**Screenshots**
![image](https://github.com/user-attachments/assets/6f9e7784-8856-4750-a0e5-31e93d71ff53)


**Desktop (please complete the following information):**
 - OS: Ubuntu 20.04.3 LTS
 - pydeseq2: 0.4.12

**Additional context**
The behaviour is not stable based on the name of groups. If i exchange A to B the values are different and the overflow error doent pop up, however the results are still suspicious. The data i can not publicly share, but potentially i would be able to share them withthout geneids. The most weird and unstable behaviour was seen in genes with high expression.

### Additional contract requirements

- For the five-gene large-count comparison, use this count matrix, with rows as samples and columns as genes:

  | Sample | g1 | g2 | g3 | g4 | g5 | Condition |
  |---|---:|---:|---:|---:|---:|---|
  | A1 | 25 | 405 | 1355 | 12558 | 489843 | A |
  | A2 | 28 | 480 | 2144 | 13844 | 514571 | A |
  | A3 | 12 | 690 | 1919 | 15632 | 564106 | A |
  | A4 | 31 | 420 | 1684 | 11513 | 556380 | A |
  | B1 | 34 | 278 | 3849 | 11577 | 412551 | B |
  | B2 | 19 | 249 | 3086 | 7296 | 295565 | B |
  | B3 | 17 | 491 | 4089 | 13805 | 280945 | B |
  | B4 | 15 | 251 | 2785 | 10492 | 214062 | B |

- For the B-versus-A condition effect on this example, the shrunk log2 fold changes must agree with the corresponding DESeq2 apeglm reference results to within 2% maximum relative error.
