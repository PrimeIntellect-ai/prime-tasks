Failing dask/bytes/tests/test_local.py with fsspec master
cc @martindurant

```
========================================================================= FAILURES =========================================================================
______________________________________________________________ test_urlpath_inference_errors _______________________________________________________________

    def test_urlpath_inference_errors():
        # Empty list
        with pytest.raises(ValueError, match="empty"):
            get_fs_token_paths([])

        # Protocols differ
        with pytest.raises(ValueError, match="the same protocol"):
>           get_fs_token_paths(["s3://test/path.csv", "/other/path.csv"])

dask/bytes/tests/test_local.py:74:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

urlpath = ['s3://test/path.csv', '/other/path.csv'], mode = 'rb', num = 1, name_function = None, storage_options = None, protocol = None, expand = True

    def get_fs_token_paths(
        urlpath,
        mode="rb",
        num=1,
        name_function=None,
        storage_options=None,
        protocol=None,
        expand=True,
    ):
        """Filesystem, deterministic token, and paths from a urlpath and options.

        Parameters
        ----------
        urlpath: string or iterable
            Absolute or relative filepath, URL (may include protocols like
            ``s3://``), or globstring pointing to data.
        mode: str, optional
            Mode in which to open files.
        num: int, optional
            If opening in writing mode, number of files we expect to create.
        name_function: callable, optional
            If opening in writing mode, this callable is used to generate path
            names. Names are generated for each partition by
            ``urlpath.replace('*', name_function(partition_index))``.
        storage_options: dict, optional
            Additional keywords to pass to the filesystem class.
        protocol: str or None
            To override the protocol specifier in the URL
        expand: bool
            Expand string paths for writing, assuming the path is a directory
        """
>       chain = _un_chain(urlpath, storage_options or {})

../../Envs/dask-dev/lib/python3.7/site-packages/fsspec/core.py:484:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

path = ['s3://test/path.csv', '/other/path.csv'], kwargs = ({}, {})

    def _un_chain(path, kwargs):
        if isinstance(path, (tuple, list)):
            bits = [_un_chain(p, kwargs) for p in path]
            out = []
            for pbit in zip(*bits):
                paths, protocols, kwargs = zip(*pbit)
                if len(set(protocols)) > 1:
>                   raise ValueError("Protocol mismatch in URL chain")
E                   ValueError: Protocol mismatch in URL chain

../../Envs/dask-dev/lib/python3.7/site-packages/fsspec/core.py:258: ValueError

During handling of the above exception, another exception occurred:

    def test_urlpath_inference_errors():
        # Empty list
        with pytest.raises(ValueError, match="empty"):
            get_fs_token_paths([])

        # Protocols differ
        with pytest.raises(ValueError, match="the same protocol"):
>           get_fs_token_paths(["s3://test/path.csv", "/other/path.csv"])
E           AssertionError: Pattern 'the same protocol' does not match 'Protocol mismatch in URL chain'

dask/bytes/tests/test_local.py:74: AssertionError
_____________________________________________________________________ test_with_paths ______________________________________________________________________

    @pytest.mark.skipif(sys.platform == "win32", reason="pathlib and moto clash on windows")
    def test_with_paths():
        with filetexts(files, mode="b"):
            url = pathlib.Path("./.test.accounts.*")
>           sample, values = read_bytes(url, blocksize=None)

dask/bytes/tests/test_local.py:215:
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
dask/bytes/core.py:93: in read_bytes
    fs, fs_token, paths = get_fs_token_paths(urlpath, mode="rb", storage_options=kwargs)
../../Envs/dask-dev/lib/python3.7/site-packages/fsspec/core.py:484: in get_fs_token_paths
    chain = _un_chain(urlpath, storage_options or {})
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

path = PosixPath('.test.accounts.*'), kwargs = {}

    def _un_chain(path, kwargs):
        if isinstance(path, (tuple, list)):
            bits = [_un_chain(p, kwargs) for p in path]
            out = []
            for pbit in zip(*bits):
                paths, protocols, kwargs = zip(*pbit)
                if len(set(protocols)) > 1:
                    raise ValueError("Protocol mismatch in URL chain")
                if len(set(paths)) == 1:
                    paths = paths[0]
                else:
                    paths = list(paths)
                out.append([paths, protocols[0], kwargs[0]])
            return out
        x = re.compile(".*[^a-z]+.*")  # test for non protocol-like single word
        bits = (
            [p if "://" in p or x.match(p) else p + "://" for p in path.split("::")]
>           if "::" in path
            else [path]
        )
E       TypeError: argument of type 'PosixPath' is not iterable

../../Envs/dask-dev/lib/python3.7/site-packages/fsspec/core.py:268: TypeError
================================================================ slowest 10 test durations =================================================================

(0.00 durations hidden.  Use -vv to show these durations.)
==================================================================== 2 failed in 0.49s =====================================================================
```

### Additional contract requirements

- `read_bytes(urlpath, blocksize=None, **kwargs)` in `dask.bytes.core` accepts a string, an `os.PathLike` value, or a list or tuple of such paths (including glob patterns). Passing any other type, such as a `set`, raises `TypeError` with the message "Path should be a string, os.PathLike, list or tuple".
- `read_bytes` returns a tuple `(sample, values)`, where `sample` is the first block of the data and `values` is a collection of the remaining blocks.
- `get_fs_token_paths` in `dask.bytes.core` raises `ValueError` with a message containing "empty" when given an empty list of paths.
- `get_fs_token_paths` raises `ValueError` when given a list of paths that use different protocols.
