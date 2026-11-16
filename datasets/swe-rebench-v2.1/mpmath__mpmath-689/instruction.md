Strange matrix behaviour
```
Python 3.4.3 (default, Oct 14 2015, 20:33:09)
[GCC 4.8.4] on linux
Type "help", "copyright", "credits" or "license" for more information.

>>> import mpmath as mpm
>>> M=mpm.zeros(1,1)
>>> M[:,1]
>>> matrix(
>>> [['0.0']])
>>> M[0,1]
>>> Traceback (most recent call last):
>>>   File "<stdin>", line 1, in <module>
>>>   File "/usr/lib/python3/dist-packages/mpmath/matrices/matrices.py", line 490, in **getitem**
>>>     raise IndexError('matrix index out of range')
>>> IndexError: matrix index out of range
>>> M.rows
>>> 1
>>> M.cols
>>> 1
>>> mpm.**version**
>>> '0.18'
```
