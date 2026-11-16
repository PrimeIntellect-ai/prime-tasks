`learn_rounding_digits` should work for numerical data of `object` dtype
### Problem Description
The `learn_rounding_digits` method may raise the following error when running on numerical data of dtype `object`: ```TypeError: loop of ufunc does not support argument 0 of type float which has no callable rint method```.

This happens because pandas.Series doesn't support rounding when `dtype=object` for versions 2.1 or lower of pandas.

### Expected behavior
The `learn_rounding_digits` method should accept as input pandas.Series of numerical data with dtype `object`.
