Stop using df.append in codebase to resolve warning
- In building the Featuretools docs I saw this warning
```python
/Users/gaurav.sheni/.pyenv/versions/3.9.13/lib/python3.9/site-packages/woodwork/type_sys/utils.py:132: FutureWarning: The frame.append method is deprecated and will be removed from pandas in a future version. Use pandas.concat instead.
```
- [HIDDEN]
- Completion: No more `.append` calls in Woodwork
