Add mpf.__format__() dunder methods
I am struggling with the conversion of a script written for Python 2.7 to Python 3 (PS: I know Python 3 still understands the old formatting syntax, but I would like to convert to the new formatting syntax as well). Consider the following example (IPython with output):

    In [1]: import mpmath

    In [2]: value = mpmath.mp.mpf('1.0')

    In [3]: print('%10.0f' % value)
             1

    In [4]: print('{:10.0f}'.format(value))
    ---------------------------------------------------------------------------
    TypeError                                 Traceback (most recent call last)
    <ipython-input-4-f8a6817daeeb> in <module>()
    ----> 1 print('{:10.0f}'.format(value))

Is there a sensible fix for this?

I have tried:

     print('{:10s}'.format(mpfloat.nstr(value)))

instead, but I cannot seem to figure out how to configure `nstr` to behave like line 3 above. The latter seems to perform rounding of some numbers that the former does not...
