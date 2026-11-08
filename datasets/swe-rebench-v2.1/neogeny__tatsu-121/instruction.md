Void doesn't end recursion
```python
    def test_nullable_void(self):
        left_grammar = '''
            @@left_recursion :: True
            @@nameguard :: False

            start = A $ ;
            A = | A 'a' | () ;
        '''

        assert [['a', 'a'], 'a'] == parse(left_grammar, 'aaa')  # warning: infinite recursion
```
