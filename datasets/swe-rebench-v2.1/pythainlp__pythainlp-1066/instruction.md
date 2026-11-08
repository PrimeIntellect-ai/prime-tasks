bug: Should raise error for using custom dict with unsupported word tokenization engine
### Description

Should raise an error when `custom_dict` is passed into `word_tokenizer` function but the selected engine is not supported custom_dict

### Expected results

Should either:
1. Raise `NotImplementedError` if the user passed in custom_dict to unsupported tokenizer engines
or
2. Raise a warning

### Current results

The current code completely ignores custom dict behavior when its engine not supported

https://github.com/PyThaiNLP/pythainlp/blob/3aa57c6bc62bdb91b6e1713303fcfa7e15855b1b/pythainlp/tokenize/core.py#L228-L235

### Steps to reproduce

```python
from pythainlp.tokenize import word_tokenize
from pythainlp.util import dict_trie


custom_dict = dict_trie(set(['tsts']))
word_tokenize('tstshel', custom_dict=custom_dict, engine = 'attacut')
```

### PyThaiNLP version

Commit hash 3aa57c6

### Python version

all

### Operating system and version

all

### More info

_No response_

### Possible solution

_No response_

### Files

_No response_
