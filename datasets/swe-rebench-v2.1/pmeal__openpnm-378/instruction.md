find_connected_pores fails given empty list
It works unless flatten is True

### Additional contract requirements

Calling `find_connected_pores` with an empty throat selection must return an empty result for both `flatten=True` and `flatten=False`.
