with_argument_list breaks when using preserve_quotes argument
The following function causes this exception
`TypeError: with_argument_list() missing 1 required positional argument: 'func'`

```Python
@with_argument_list(preserve_quotes=True)
    def do_blah(self, args):
        print(args)
```
