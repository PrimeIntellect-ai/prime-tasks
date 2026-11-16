Incorrect platform tag returned for GraalPy
When running a 64-bit version of GraalPy (either x86_64 or aarch64), packaging returns the wrong platform tag (either i686 or armv8l).

Attempt to fix in https://github.com/pypa/packaging/pull/614 which is now closed.
Hopefully, https://github.com/python/cpython/issues/103483 might help in the future but, for now and for already released python interpreters versions, a fix is needed in packaging.

cc @timfel
