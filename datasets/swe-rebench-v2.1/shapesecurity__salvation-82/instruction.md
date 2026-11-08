'self' in source list is not resolved during the optimisation
Example:
policy `object-src example.com *` served by example.com is optimised to empty policy ""

`object-src 'self' *` remains unmodofied
