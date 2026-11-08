Port changes to reduce dependencies on ctypes module in packaging.tags.
Benefits as mentioned in the linked issues on PR pypa/pip#6678:

* reduces dependency on ctypes
* allows usage from a statically-linked Python
