Dispatch API raises assertion error?
Some classes `raises` AssertionError if parse is not succeeded.
But should we always return `None` when URL is invalid? Since such inputs are possible in user applications.
```python
>>> dispatch.problem_from_url("https://yukicoder.me/contests/241/")  # Assert raises
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/ryo/workspace/github/online-judge-tools/onlinejudge/dispatch.py", line 53, in problem_from_url
    problem = cls.from_url(url)
  File "/home/ryo/workspace/github/online-judge-tools/onlinejudge/service/yukicoder.py", [HIDDEN]
  File "/home/ryo/workspace/github/online-judge-tools/onlinejudge/service/yukicoder.py", [HIDDEN]
AssertionError
>>> dispatch.problem_from_url("https://yahoo.co.jp")  # return None

```

### Additional contract requirements

- `dispatch.problem_from_url(url)` must return `None` whenever the URL cannot be interpreted as identifying a problem, including URLs for a supported service that do not identify a problem. It must not raise `AssertionError` for such URLs.
