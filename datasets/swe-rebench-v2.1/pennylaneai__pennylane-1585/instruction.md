Allow QNodes to support `diff_method=None` option
As discussed in #1271 , add the option for `diff_method=None` to QNodes. This would create QNodes that accept NumPy input, return NumPy output, but cannot be differentiated.
