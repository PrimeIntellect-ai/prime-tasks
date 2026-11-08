Feature Request: dom child iteration via __iter__
## Is your feature request related to a problem? Please describe
Not really a "problem". More that I find it not terribly intuitive to write dom._pfp__children.

## Describe the solution you'd like
My natural response to iterating through a list of object is to use something like "for item in dom". In this case, my proposed solution would be to implement `__iter__` as simply `[HIDDEN]`.

## Describe alternatives you've considered
Currently I just reference ._pfp__children when I want to see the listing.

## Additional context
N/A

### Additional contract requirements

- A parsed array value supports iteration: `for item in some_array` yields each element object of the array in order.
- The array type exposes a public `__iter__` method that returns an iterator over the array's element objects.
- A parsed struct value supports iteration: `for field in some_struct` yields its child fields in definition order.
