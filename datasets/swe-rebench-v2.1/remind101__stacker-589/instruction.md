stacker.status.Status.__cmp__ implementation is wrong
Came across [this](https://github.com/remind101/stacker/blob/db2119270a6d903f5bba6e830b2818769957bc28/stacker/status.py#L7) while adding python3 support and it feels like there could be some subtle fallout. [Per the docs](https://docs.python.org/2/reference/datamodel.html#object.__cmp__) this is supposed to return zero iff the objects are equal, and since ```False == 0``` any Status is equal to any object without a code attribute. The only reason I stumbled across it is ```__cmp__``` isn't supported in py3 and one of the tests fails (forget which offhand), but the test compares a Status to True which currently always succeeds:

```
Python 2.7.8 (default, Oct 18 2017, 15:41:14)
[GCC 4.2.1 Compatible Apple LLVM 8.1.0 (clang-802.0.42)] on darwin
Type "help", "copyright", "credits" or "license" for more information.
>>> import stacker.status
>>> stacker.status.SUBMITTED == stacker.status.PENDING
False
>>> stacker.status.SUBMITTED == True
True
>>> stacker.status.SUBMITTED == False
True
>>> stacker.status.SUBMITTED == 'banana'
True
>>>
```

Everything I needed for py3 support was obvious and mechanical except this.
