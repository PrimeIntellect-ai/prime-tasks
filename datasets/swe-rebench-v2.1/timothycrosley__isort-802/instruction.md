Monkey patching urllib not ideal
We recently had some (python 3 only) code that was erroneously doing
```
from urllib import quote
```
which was working in tests but not in production. The reason being that isort was being loaded in tests and monkey patches urllib at https://github.com/timothycrosley/isort/blob/develop/isort/pie_slice.py#L115. It would have been nice not to have to debug this, so can we update isort not to do this patch?

It doesn't even seem to use urllib...
