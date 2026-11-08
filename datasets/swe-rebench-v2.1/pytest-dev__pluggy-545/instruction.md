StopIteration passtrough not handled correctly
[cpython impl ref in contextmanager](https://github.com/python/cpython/blob/ac00bf0e96d93adf20879217dc7022c7c3a5dc89/Lib/contextlib.py#L173C65-L184)


a test in one of my testsuites failed with a StopIteration as exception

this ran into issues as new style hook wrappers dont manage the RuntimeError of stopIteration

```
>>> def mygen(): yield
...
>>> gen = mygen()
>>> next(gen)
>>> e = StopIteration()
>>> try:
...   gen.throw(e)
... except Exception as err:
...   runtime = err
...
>>> runtime
RuntimeError('generator raised StopIteration')
>>> runtime.
runtime.add_note(        runtime.args             runtime.with_traceback(
>>> runtime.a
runtime.add_note(  runtime.args
>>> runtime.args
('generator raised StopIteration',)
>>> runtime.__cause__
StopIteration()
>>> runtime.__cause__ is e
True
>>>
