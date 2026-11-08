Python Enum support for click.Choice
I can work  around it as [described here](https://pythonpath.wordpress.com/2012/01/26/python-enum-with-namedtuple/) it would be great if `Choice` supported Python Enum.

Unless of course I have missed something completely fundamental :-)

### Additional contract requirements

- `Choice` accepts any iterable of values, including non-string values such as
  `enum.Enum` members, `None`, and arbitrary objects, and conversion returns the
  original choice object that corresponds to the supplied token.
- Enum choices are represented on the command line by their member name, not by
  their value. For an `enum.Enum` member such as `MyEnum.FOO`, the accepted
  token is the member name (`FOO`), case-folded to `foo` when
  `case_sensitive=False`. Metavars and invalid-choice messages display these
  normalized names, e.g. `{foo|bar|baz}` and
  `'meh' is not one of 'foo', 'bar', 'baz'.`
