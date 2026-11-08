5.0.0 fails to parse args
Hi,
Looks like you are about to release `5.0.0` but it already gets fetched by `jupyter` :
```shell
docker run --rm -it python:3.7 bash
$ pip install jupyter
...
Collecting traitlets>=4.2
  Downloading traitlets-5.0.0-py3-none-any.whl (97 kB)
...
```
And leads to an exception in my tests, you may try to reproduce with:
```
$ python
>> from nbconvert import nbconvertapp
>> nbconvertapp.main(["nbconvert", "--output", "/tmp/qwe.txt", "simple-py36.ipynb"])
...
: error: unrecognized arguments: simple-py36.ipynb
...
```
I have fixed it by pinning to `traitlets>=4.2,<5.0.0`.

### Additional contract requirements

The regression is in `Bytes.from_string` (and its subclass `CBytes.from_string`). Command-line values for `Bytes`/`CBytes` traits that use the deprecated `b"..."` / `b'...'` quoting syntax must be parsed to the inner bytes, emitting a `FutureWarning`; `"None"` maps to `None` only when `allow_none` is True.
