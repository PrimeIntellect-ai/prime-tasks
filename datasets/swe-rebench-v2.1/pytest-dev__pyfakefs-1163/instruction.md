Bug: FakeFileOpen objects don't implement the mode property required by typing.io.IO
**How To Reproduce**
```
from pyfakefs.fake_filesystem import FakeFilesystem
from pyfakefs.fake_open import FakeFileOpen
from pyfakefs.fake_pathlib import FakePathlibModule

fake_fs = FakeFilesystem()
fake_open = FakeFileOpen(fake_fs)
fake_pathlib = FakePathlibModule(fake_fs)

f = open("test.txt")
assert f.mode  # This works fine

fake_pathlib.Path("test.txt").write_text(f.read())
f_ = fake_open("test.txt")
assert f_.mode  # This fails
```

**Expected behavior:**
Fake file objects should properly implement the mode property as required by the typing.io.IO abstract class:

```
class IO(Generic[AnyStr]):
    @property
    @abstractmethod
    def mode(self) -> str:
        pass
```

**Your environment**
python3.9
pyfakefs==5.8.0

### Additional contract requirements

- The `mode` property of a file object returned by `open` on the fake filesystem returns a `str`.
- The returned string describes the mode the file was opened with: whether it is binary or text, and which access it permits (reading, writing, appending, or exclusive creation, including the read+write variants).
- Text modes may be reported either with or without the explicit text marker `t` (for example `"r"` and `"rt"` are both acceptable for a text file opened for reading).
