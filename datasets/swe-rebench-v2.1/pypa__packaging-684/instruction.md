URI parsing
```
$ python3
Python 3.6.4 (default, Jan  6 2018, 02:24:08)
[GCC 7.2.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import packaging.requirements
>>> packaging.requirements.Requirement("pip @ file://localhost/localbuilds/pip-1.3.1-py33-none-any.whl")
<Requirement('pip@ file://localhost/localbuilds/pip-1.3.1-py33-none-any.whl')>
>>> packaging.requirements.Requirement("pip @ file:///localbuilds/pip-1.3.1-py33-none-any.whl")
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/uken/.local/lib64/python3.6/site-packages/packaging/requirements.py", line 101, in __init__
    raise InvalidRequirement("Invalid URL given")
packaging.requirements.InvalidRequirement: Invalid URL given
```

According to [PEP 508](https://www.python.org/dev/peps/pep-0508/) the following strings should all be parseable:

```
"pip @ file://localhost/localbuilds/pip-1.3.1-py33-none-any.whl"
"pip @ file:///localbuilds/pip-1.3.1-py33-none-any.whl"
"pip @ /localbuilds/pip-1.3.1-py33-none-any.whl"
"pip @ localbuilds/pip-1.3.1-py33-none-any.whl"
```

(I have fed them into the "test program" included in PEP 508 that uses `Parsley` for parsing. Note that there are several typos in the grammar in the document text)

The following logic may be flawed:

https://github.com/pypa/packaging/blob/d2ed39a1383b00f9c867c854b708f7c102672898/packaging/requirements.py#L102-L104
