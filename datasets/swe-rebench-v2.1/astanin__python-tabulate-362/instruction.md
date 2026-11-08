Can not tabulate row with a field that looks like a Python Bool using maxcolwidths
The following line will fail with an error about "bool' object has no attribute 'expandtabs'

    tabulate.tabulate([['init','True']], maxcolwidths=[None, 42])

This happens because [HIDDEN]  Unfortunately [HIDDEN] expects a str according to it's docstring and so explodes when passed a bool

My quick naïve reading suggests you could [HIDDEN]; if your next call only accepts a str [HIDDEN]  Still I'll leave it to those that know the code better then ignorant me to figure out the best fix.

Also completely random nitpick, but I noticed the _type method docstring lists other types it will convert, but does not include bool in it's description despite checking for and handling bools so may want to update that for consistency.

### Additional contract requirements

- When a cell contains the string `True`, calling `tabulate` with `maxcolwidths` must complete successfully and include that cell's text in the tabulated result.
