CPython 3.8 debug/release wheel ABI compatibility
Per [bpo-36465](https://bugs.python.org/issue36465), Python 3.8 will support libraries compiled against a release build running in a debug build of the interpreter.

Pip could make this easier to take advantage of by allowing e.g. cp38dm and cp38m wheels in a debug Python 3.8. If we are planning to switch to `packaging.tags` then that may be the place to make the actual changes and this issue could be closed or track the integration.

**Additional context**

* pypa/pip#5733
* [python-dev mailing list](https://mail.python.org/pipermail/python-dev/2019-April/157178.html) by @vstinner
