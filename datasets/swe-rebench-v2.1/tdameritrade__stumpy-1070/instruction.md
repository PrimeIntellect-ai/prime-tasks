Wrong Numba Cache Directory
@NimaSarajpoor  [Had asked](https://github.com/TDAmeritrade/stumpy/issues/1066#issuecomment-2617797555):

> I think we should open an issue for https://github.com/TDAmeritrade/stumpy/pull/1067#discussion_r1930017203. This can help us to track it separately. What do you think?

This is the corresponding ticket in response to his question.

From what I understand, once a package is installed, the `nbc`/`nbi` files are typically written to the `site-packages/stumpy/__pycache__` subdirectory if a user imports `stumpy`. However, specifically for `pytest`, cache files are written locally in `stumpy/__pycache__` because `pytest` isn't using the installed package and, instead, are using the files from the local `stumpy/*py`! So, when a user uses `stumpy`, caching occurs in site-packages and all is well (since `cache._clear()` targets `site-packages/stumpy/__pycache__`. However, for unit testing, we get a different behavior because `pytest` is basically running things locally (i.e., it is creating the bytecode locally and not from `site-packages`) and accessing the bytecode/cache from `stumpy/__pycache__` rather than from `site-packages/stumpy/__pycache__`. In other words, `pytest` isn't using the installed stumpy and, instead, `pytest` is using/importing local `stumpy` and creating the bytecode locally (independent of the installed package in site-packages).

So, it's a bit misleading when we do `./setup.sh && ./test.sh` 😢

Note, that this (cache directory) behavior should NOT be observed from an end user's standpoint (i.e., when `stumpy` is installed and accessed from site-packages) and should only affect unit testing.
