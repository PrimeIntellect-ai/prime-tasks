misformatted output of unknown rules since 5.6.0
Since version 5.6.0, TatSu's output of unknown rules in grammars is misformatted:

```

import tatsu

GRAMMAR = '''
@@grammar::TestGrammar

  block = test ;


'''
if __name__ == '__main__':
    import pprint
    from tatsu import parse

    ast = parse(GRAMMAR, 'abc')
    pprint.pprint(ast, indent=2, width=20)

```

will output
```
tatsu.exceptions.GrammarError: Unknown rules, no parser generated:
e
s
t
```

In version 5.5.0, it was
```
tatsu.exceptions.GrammarError: Unknown rules, no parser generated:
test
```

### Additional contract requirements

- When the unknown rules are `test` and `test2`, the error message must be exactly `Unknown rules, no parser generated:\ntest\ntest2`.
