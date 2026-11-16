`pyfakefs` tests appear to throw on the latest spot releases of Python 3.11 and 3.12
**Describe the bug**
Versions 3.11.13 and 3.12.11 (released June 3rd) appear to have broken our tests in [Conda Recipe Manager](https://github.com/conda/conda-recipe-manager). We are using `conda` as our environment manager. If we revert to older versions of Python, our tests go back to passing.

```
Exception ignored in: <function MockHttpStreamResponse.__del__ at 0x7f8a64e0d620>
Traceback (most recent call last):
  File "/home/runner/work/conda-recipe-manager/conda-recipe-manager/tests/http_mocking.py", line 135, in __del__
  File "/usr/share/miniconda/envs/conda-recipe-manager/lib/python3.11/site-packages/pyfakefs/fake_file.py", line 853, in close
  File "/usr/share/miniconda/envs/conda-recipe-manager/lib/python3.11/site-packages/pyfakefs/fake_file.py", line 865, in close_fd
  File "/usr/share/miniconda/envs/conda-recipe-manager/lib/python3.11/site-packages/pyfakefs/fake_file.py", line 941, in flush
  File "/usr/share/miniconda/envs/conda-recipe-manager/lib/python3.11/site-packages/pyfakefs/fake_filesystem.py", line 430, in raise_os_error
OSError: [Errno 9] Bad file descriptor in the fake filesystem
```

^ This is a small snipped of the stack trace we are seeing in the tests. You can see my full notes and links to example GHA runs in this issue: https://github.com/conda/conda-recipe-manager/issues/369

We had been tracking a `pyfakefs` clean-up warning for a while [here](https://github.com/conda/conda-recipe-manager/issues/237), but have not had time to investigate. It is unclear if these are related or not.

**How To Reproduce**
Install one of the latest Python patch versions noted above. There could be more, but we know for sure that 3.11.11 works fine. Again, there are examples in the GitHub Action runs linked in Conda Recipe Manager's Tracking ticket.

Using Anaconda's primary channel (`defaults`) we install `pyfakefs@5.6.0`. I briefly ran a test last night that uses the `conda-forge` channel. That installed the latest version `conda-forge` currently releases and that is `pyfakefs@5.7.4`. I did not see any changes between the two versions on the afflicted Python versions.

Additionally, assuming you have `conda` installed, you can clone Conda Recipe Manager, run `make dev` and run `conda activate conda-recipe-manager && make test` to reproduce this issue. Note that by the time you read this, you may have to explicitly set the `python` version in our `environment.yaml` file (I'm actively working on a stop gap fix to hard-code the Python version used).

Alternatively you can use the provided `environment.yaml` file with the packaging system of your choosing (though obviously I have not tested outside of `conda`).

**Your environment**
Please run the following in the environment where the problem happened and
paste the output.
```bash
python -c "import platform; print(platform.platform())"
python -c "import sys; print('Python', sys.version)"
python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
python -c "import pytest; print('pytest', pytest.__version__)"
```

From the conda environment on my development Mac (I did not run this on our default GHA runner environment):
```
$ python -c "import platform; print(platform.platform())"
macOS-15.4.1-arm64-arm-64bit
$ python -c "import sys; print('Python', sys.version)"
Python 3.11.13 (main, Jun  5 2025, 08:21:08) [Clang 14.0.6 ]
$ python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
pyfakefs 5.6.0
$ python -c "import pytest; print('pytest', pytest.__version__)"
pytest 8.3.4
```

Thanks for your help! We appreciate your hard work on this project; it continues to work very well for our needs!

### Additional contract requirements

When the fake `os.path.realpath` is called with `strict=os.path.ALLOW_MISSING`, it resolves the existing portion of a path even if later components are absent and returns the normalized path. It ignores `FileNotFoundError` but continues to raise other resolution errors, such as a symlink loop.

A fake file used while resolving a path must be cleanly closable; cleanup must not raise the reported bad-file-descriptor error.
