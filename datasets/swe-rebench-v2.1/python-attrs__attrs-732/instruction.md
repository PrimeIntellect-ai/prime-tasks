Make bool(attr.NOTHING) == False
`attr.NOTHING` describes an non-existing/unset attribute in an object.
However, `bool(attr.NOTHING)` currently evaluates to True which is unnatural and does not really fit.

## Other python empty values

The meaning of `attr.NOTHING` is very near to `None` but in contrast the latter one evaluates to False.

It is also very common that ‘empty-values’ evaluates to False in Python:

```python
>>> import attr
>>> bool(attr.NOTHING)
True
>>> bool(None)
False
>>> bool('')
False
>>> bool([])
False
>>> bool({})
False
```

And `bool(attr.NOTHING)` does not fit there.

## If case ‚non-empty‘ value

When I want to process a non-empty value I would naturally write:

```python
# foo is here an instance of an attrs decorated class with the bar attribute

if foo.bar:
    ... # Do something on a non-empty value
```

However, the above if case would enter if `bar` is `attr.NOTHING`.
Hence, you have to write:

```python
if foo.bar is not attr.NOTHING and foo.bar:
    ... # Do something on a non-empty value
```

And this is kind of wired and can be easily forgotten (Like me until I found out that `attr.NOTHING` is True ;-) ).

I am aware that usually an instance attribute should normally not be assigned with `attr.NOTHING`, but an Exception should be raised somewhere. However, with an own init, wrappers, not so simple cases, or custom converters, this can happen – and in this case I would expect that `attr.NOTHING` is behaving like other python empty-values and that `if foo.bar` would not be entered.

## Interface change

Making `bool(attr.NOTHING) == False` would be a more or less severe interface change.
Is `bool(attr.NOTHING) == False` on purpose for some reason?
Like I said attributes should normally not be assigned with `attr.NOTHING`, so it might be a rare case; and direct tests if something is `attr.NOTHING` should be done by `some_value is attr.NOTHING` anyway – or in other words is someone already relying on the fact that `bool(attr.NOTHING) == True`? Then it would be a severe change, but I guess not.

So lets change bool(attr.NOTHING) to False [HIDDEN]
