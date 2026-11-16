Use `__slots__` for observer internals
The observation framework has a lot of classes which are small and with a fixed set of attributes.  Using `__slots__` on these classes will save memory and give a small performance boost when the attribtutes are accessed.
