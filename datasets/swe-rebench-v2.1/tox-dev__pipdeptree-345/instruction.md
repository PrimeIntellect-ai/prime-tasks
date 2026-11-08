Error with a certain version constraint format
### What pipdeptree version are you using?

2.17.0

### Are you running pipdeptree in a virtual environment?

- [ ] Yes

### Describe the problem

Thank you for developing a great library!

We use `pipdeptree` in our CIs, and it fails in v2.17.0 but passes in v2.16.2.
https://github.com/optuna/optuna-integration/pull/109
```
Traceback (most recent call last):
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/requirements.py", line 35, in __init__
    parsed = _parse_requirement(requirement_string)
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/_parser.py", line 64, in parse_requirement
    return _parse_requirement(Tokenizer(source, rules=DEFAULT_RULES))
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/_parser.py", line 82, in _parse_requirement
    url, specifier, marker = _parse_requirement_details(tokenizer)
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/_parser.py", line 120, in _parse_requirement_details
    specifier = _parse_specifier(tokenizer)
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/_parser.py", line 210, in _parse_specifier
    with tokenizer.enclosing_tokens(
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/contextlib.py", line 142, in __exit__
    next(self.gen)
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/_tokenizer.py", line 187, in enclosing_tokens
    self.raise_syntax_error(
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/_tokenizer.py", line 165, in raise_syntax_error
    raise ParserSyntaxError(
packaging._tokenizer.ParserSyntaxError: Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after version specifier
    scikit-image (<0.[19](https://github.com/optuna/optuna-integration/actions/runs/8562392755/job/23465560814#step:7:20).0>=0.16.1) ; extra == 'all'
                 ~~~~~~~~^

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "/opt/hostedtoolcache/Python/3.10.14/x64/bin/pipdeptree", line 8, in <module>
    sys.exit(main())
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/pipdeptree/__main__.py", line 24, in main
    tree = PackageDAG.from_pkgs(pkgs)
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/pipdeptree/_models/dag.py", line 47, in from_pkgs
    for r in p.requires():
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/pipdeptree/_models/package.py", line 102, in requires
    req = Requirement(r)
  File "/opt/hostedtoolcache/Python/3.10.14/x64/lib/python3.10/site-packages/packaging/requirements.py", line 37, in __init__
    raise InvalidRequirement(str(e)) from e
packaging.requirements.InvalidRequirement: Expected matching RIGHT_PARENTHESIS for LEFT_PARENTHESIS, after version specifier
    scikit-image (<0.19.0>=0.16.1) ; extra == 'all'
                 ~~~~~~~~^
```

I guess that the cause of this error is the incorrect format of `catalyst`.
https://github.com/catalyst-team/catalyst/blob/v22.04/requirements/requirements-cv.txt#L3
```
scikit-image<0.19.0>=0.16.1
```
