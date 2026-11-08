McNemar's test mcnemar_table off diagonal entries are swapped
Hi Sebastian,

the tb[1,0] and tb[0,1] entries in the 2x2 contigency table for McNemar's test in _mcnemar_table_ are swapped: https://github.com/rasbt/mlxtend/blob/master/mlxtend/evaluate/mcnemar.py#L63

While it should not affect the test statistic, the layout is not consistent with the one you describe here: https://arxiv.org/abs/1811.12808 (Figure 19 and Figure 20)

Best,
Marius

### Additional contract requirements

- The corrected layout also applies to the public function `mcnemar_tables(y_target, *y_model_predictions)` in module `mlxtend.evaluate`: each 2x2 contingency table it returns must have `tb[0, 1]` equal to the number of samples that model 1 predicted correctly and model 2 predicted incorrectly, and `tb[1, 0]` equal to the number of samples that model 2 predicted correctly and model 1 predicted incorrectly.
