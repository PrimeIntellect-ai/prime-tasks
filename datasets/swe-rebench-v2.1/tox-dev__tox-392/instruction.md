Consider supporting 'py2' and 'py3' default environments
- Bitbucket: https://bitbucket.org/hpk42/tox/issue/348
- Originally reported by: [tobias.mcnulty](http://bitbucket.org/tobias.mcnulty)
- Originally created at: 2016-07-19T22:12:41.440


For packages where I want to test *some* version of python3 but I don't really care which one, support for `py2` and `py3` environments would be nice, e.g.:

	[testenv:py2]
	basepython = python2

	[testenv:py3]
	basepython = python3

I can create these easily enough myself, but thought I'd submit this issue in case anyone else would find it useful.
