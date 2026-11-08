failure to load grammar from cache
(this is a follow-up on an issue encountered in #992)
```python
import logging

from lark import Lark, logger
from lark.visitors import Transformer, merge_transformers, v_args

logger.setLevel(logging.ERROR)


@v_args(inline=True)
class MergedTransformer(Transformer):
    SOMETHING = str


class MainTransformer(Transformer):
    pass


transformer = merge_transformers(
    MainTransformer(),
    merged=MergedTransformer()
)

parser = Lark(
    'start: "a"',
    parser='lalr',
    transformer=transformer,
    cache='cached_grammar',
    debug=True
)
```
in this minimal example, running the code for a second time (first we need to create the cached grammar) will result in this error being raised:
```python
Failed to load Lark from cache: 'cached_grammar'. We will try to carry on.
Traceback (most recent call last):
  File "C:\Python39\lib\site-packages\lark-1.0.0a0-py3.9.egg\lark\lark.py", line 319, in __init__
    cached_parser_data = pickle.load(f)
AttributeError: 'MergedTransformer' object has no attribute 'str'
```
