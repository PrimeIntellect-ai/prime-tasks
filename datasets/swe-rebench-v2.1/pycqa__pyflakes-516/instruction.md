Spurious unsued import warning for type annotation used in quoted cast
Given
``` python
# demo.py
from typing import Union, cast

x = cast('Union[str, int]', 42)
reveal_type(x)
```
Then I would hope that `pyflakes` would be able to see the usage of `Union` in the quoted cast, but it can't.
``` shell
$ pyflakes demo.py
demo.py:1: 'typing.Union' imported but unused
demo.py:4: undefined name 'reveal_type'
```
(`reveal_type` being undefined is correct here).

`mypy` does seem happy with this usage though.
``` shell
$ mypy demo.py
demo.py:4: error: Revealed type is 'Union[builtins.str, builtins.int]'
```

I realise this example is somewhat contrived (why would you quote this), however in the case that one of the union members is a circular import for example, you need to quote at least some part of the type and it's often cleaner to quote the whole name rather than parts of it.
