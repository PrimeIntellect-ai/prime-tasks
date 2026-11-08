FakePathlibModule shows real files on Python 3.11+ (works on 3.10)
With Python 3.11 and 3.12 the fake pathlib no longer stays inside the fake filesystem.

Calling `Path('/').iterdir()` returns the real files from the container.

On Python 3.10 the same code returns an empty list, which is what I expect.

How to reproduce:

Python 3.10  – works

```
docker run -it --rm python:3.10-alpine sh -c "
pip install -q pyfakefs && \
python - <<'PY'
from pyfakefs.fake_filesystem import FakeFilesystem
from pyfakefs.fake_pathlib import FakePathlibModule
pathlib = FakePathlibModule(FakeFilesystem())
print(list(pathlib.Path('/').iterdir()))   # expected []
PY
"
```

Python 3.12  – broken

```
docker run -it --rm python:3.12-alpine sh -c "
pip install -q pyfakefs && \
python - <<'PY'
from pyfakefs.fake_filesystem import FakeFilesystem
from pyfakefs.fake_pathlib import FakePathlibModule
pathlib = FakePathlibModule(FakeFilesystem())
print(list(pathlib.Path('/').iterdir()))   # shows real /bin, /usr, ...
PY
"
```

Why I think it breaks:
pathlib versions in newer Pythons use real os module so the fake filesystem is bypassed.
