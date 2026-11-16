allow passing your own key function to sort_together
I recently came across a situation in which I wanted to use `sort_together`, but I also wanted to sort by a custom key.
What do you think about exposing a `key` argument to `sort_together`?

I think it would also be nice for the user's key function to take only the parameters corresponding to the `key_list`, so the common case of sorting by the first is the easiest, and so the two features of `key` and `key_list` work together.

Something to this effect:

```python
[HIDDEN]


list_of_x = [1, 2, 3]
list_of_y = [4, 5, 6]

sort_together((list_of_x , list_of_y), key=lambda x: x*2)
sort_together((list_of_x , list_of_y), key_list=(1,), key=lambda y: y*2)
sort_together((list_of_x , list_of_y), key_list=(0, 1), key=lambda x, y: x*y)
```

Happy to open a PR if you like the idea.

### Additional contract requirements

- When a custom `key` function is provided, its result determines the ordering of the iterables.
- The custom key function receives only the values selected by `key_list`; when multiple values are selected, pass them as separate positional arguments.
