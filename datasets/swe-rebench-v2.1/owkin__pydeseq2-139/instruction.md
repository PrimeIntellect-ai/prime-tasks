[BUG] Design matrix check prevents use of VST without design matrix
**Describe the bug**
When creating a DDS, the latest version now checks that the design matrix is full rank; however, I only wish to use it to run VST without a design matrix.

**To Reproduce**
```
import pydeseq2.dds
import numpy as np
import pandas as pd
dds = pydeseq2.dds.DeseqDataSet(counts=np.random.poisson(0.2, (100, 200)), clinical=pd.DataFrame({'condition': np.repeat([0, 1], 50), 'condition2':np.repeat([1, 2], 50)}, index=np.arange(100)), design_factors=['condition', 'condition2'])
dds.vst(use_design=False)
```

**Expected behavior**
A clear and concise description of what you expected to happen.

**Actual behavior**
PyDeSeq2 v0.3.3: runs successfully.

PyDeSeq2 v0.3.4
```
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/scottgigante/envs/immunaISR/lib/python3.8/site-packages/pydeseq2/dds.py", line 221, in __init__
    self._check_full_rank_design()
  File "/Users/scottgigante/envs/immunaISR/lib/python3.8/site-packages/pydeseq2/dds.py", line 1007, in _check_full_rank_design
    raise ValueError(
ValueError: The design matrix is not full rank, so the model cannot be fitted. Please remove the design variables that are linear combinations of others.
```
