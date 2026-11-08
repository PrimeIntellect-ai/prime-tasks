Union trait does not parse correctly from strings
Union trait does not enumerate the types in the union when parsing from string which means that incorrect type gets inferred.

Correct inference of union types is desirable in https://github.com/jupyter-server/jupyter_server/pull/949 and https://github.com/ipython/ipython/pull/13745.
