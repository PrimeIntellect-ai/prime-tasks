The `OrderedLabelEncoder` should not accept duplicate categories
### Environment Details
* RDT version: 1.6.0 (latest)
* Python version: 3.10
* Operating System: Linux (Google Colab)

### Error Description
The [OrderedLabelEncoder](https://docs.sdv.dev/rdt/transformers-glossary/categorical/orderedlabelencoder) accepts a parameter where I input the order of the categories. The implicit requirement is that all possible categories are present only once in this parameter.

If I accidentally provide duplicate category labels, it doesn't make sense. I expect the instantiation to crash (but in reality, it somehow works).

### Steps to reproduce

```python
from rdt.transformers.categorical import OrderedLabelEncoder
from sdv.metadata import SingleTableMetadata
from sdv.single_table import GaussianCopulaSynthesizer
import pandas as pd

metadata = SingleTableMetadata.load_from_dict({
    'columns': {
        'a': { 'sdtype': 'categorical' },
        'b': { 'sdtype': 'categorical' }
    }
})

data = pd.DataFrame(data={
    'a': ['A', 'B', 'C']*2,
    'b': [1, 0.5, None]*2
})

synthesizer = GaussianCopulaSynthesizer(metadata)
synthesizer.auto_assign_transformers(data)

synthesizer.update_transformers({
    'a': UniformEncoder(),
    'b': OrderedLabelEncoder(order=[1, 0.5, None, 1]) # provide duplicate categories
})

synthesizer.fit(data)
synthesizer.sample(10)
```

### Expected
I expect an error when instantiating `OrderedLabelEncoder` with a descriptive message.

```
TransformerInputError: The OrderedLabelEncoder has duplicate categories in the 'order' parameter. Please drop the duplicates to proceed.
```
