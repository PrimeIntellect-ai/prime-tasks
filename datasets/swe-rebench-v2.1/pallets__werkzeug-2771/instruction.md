use scrypt by default
#2654 added scrypt support, but couldn't make it the default because [PyPy didn't support it at the time](https://foss.heptapod.net/pypy/pypy/-/issues/3921). Now PyPy has fixed that and [made a release](https://doc.pypy.org/en/latest/release-v7.3.12.html), I'm comfortable with making scrypt the default.
