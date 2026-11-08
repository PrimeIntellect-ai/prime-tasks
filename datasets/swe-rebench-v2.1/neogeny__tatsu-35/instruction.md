Another left recursion problem
Grammar:
```
identifier = /\w+/ ;
expr = mul | identifier ;
mul = expr '*' identifier ;
```

Parsing `a * b` with the start rule `expr` gives the expected result: `['a', '*', 'b']`. But parsing with the start rule `mul` gives the following error:
```
Traceback (most recent call last):
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 203, in parse
    result = rule()
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 54, in wrapper
    return self._call(ruleinfo)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 513, in _call
    result = self._recursive_call(ruleinfo)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 546, in _recursive_call
    result = self._invoke_rule(ruleinfo, pos, key)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 580, in _invoke_rule
    ruleinfo.impl(self)
  File "parser.py", line 96, in _mul_
    self._token('*')
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 617, in _token
    self._error(token, exclass=FailedToken)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 436, in _error
    raise self._make_exception(item, exclass=exclass)
tatsu.exceptions.FailedToken: /proc/self/fd/12(1:1) expecting '*' :

^
mul

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "parser.py", line 122, in <module>
    ast = generic_main(main, UnknownParser, name='Unknown')
  File "/home/manu/vcs/TatSu/tatsu/util.py", line 335, in generic_main
    colorize=args.color
  File "parser.py", line 115, in main
    return parser.parse(text, startrule, filename=filename, **kwargs)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 211, in parse
    raise self._furthest_exception
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 679, in _option
    yield
  File "parser.py", line 88, in _expr_
    self._mul_()
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 54, in wrapper
    return self._call(ruleinfo)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 513, in _call
    result = self._recursive_call(ruleinfo)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 546, in _recursive_call
    result = self._invoke_rule(ruleinfo, pos, key)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 580, in _invoke_rule
    ruleinfo.impl(self)
  File "parser.py", line 96, in _mul_
    self._token('*')
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 617, in _token
    self._error(token, exclass=FailedToken)
  File "/home/manu/vcs/TatSu/tatsu/contexts.py", line 436, in _error
    raise self._make_exception(item, exclass=exclass)
tatsu.exceptions.FailedToken: /proc/self/fd/12(1:1) expecting '*' :

^
mul
expr
mul
```

### Additional contract requirements

- `compile(grammar)` returns a model object that exposes a `.parse(text, start=None, trace=False, colorize=False)` method.
- For the grammar above, `model.parse('a * b', start='expr')` returns `['a', '*', 'b']`.
- The `start` argument selects the entry rule. For the grammar above, parsing `a * b` with `start='mul'` raises `FailedParse` (a subclass such as `FailedToken` is acceptable): for indirect left recursion the rule that contains the choice must be invoked first, so `mul` cannot be used as an entry point.
- Input that cannot be derived from the selected start rule raises `FailedParse`; for example `model.parse('*', start='identifier')` raises `FailedParse`.
- For the grammar `identifier = /\w+/ ; expr = mul | tmp ; mul = expr '*' tmp ; tmp = call | identifier ; call = identifier '(' ','.{expr} ')' ;`, `model.parse('a(b, c)', start='expr')` returns `['a', '(', ['b', 'c'], ')']`.
