"multi_line_output = 6" generates invalid syntax
With "multi_line_output = 6" isort generates something like:

    from a import x y z

which is not a valid import and will raise a SyntaxError. The commas are missing. With that it should be:

    from a import x, y, z

After reading the docs:
https://docs.python.org/2/reference/simple_stmts.html#import
https://docs.python.org/3/reference/simple_stmts.html#import
the comma is mandatory in all cases if there are more than one identifiers after import.

The version I use is 4.2.2 with python 2.7.
