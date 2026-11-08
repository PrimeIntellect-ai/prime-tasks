AtCoderContest.get_penalty() fails if it has a singular form, "1 minute"
``` python
$ python3 -c 'from onlinejudge.service.atcoder import * ; AtCoderContest.from_url("https://atcoder.jp/contests/chokudai_S002").get_name()'
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/user/GitHub/online-judge-tools/onlinejudge/service/atcoder.py", line 261, in get_name
    self._load_details(lang='en', session=session)
  File "/home/user/GitHub/online-judge-tools/onlinejudge/service/atcoder.py", line 255, in _load_details
    assert m
AssertionError
```
