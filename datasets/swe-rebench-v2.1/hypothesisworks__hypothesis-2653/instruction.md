Test `st.from_type()` on builtin generics from Python 3.9
Python 3.9 is coming out soon!  Happily, we're already running it in our CI - so anything that worked before still works on the new Python.  There are however also *new features*, like [PEP 585](https://www.python.org/dev/peps/pep-0585/) (type annotations using builtins as generics).

As [Guido highlights](https://twitter.com/gvanrossum/status/1313216099429695489), we should also check that everything works with `from __future__ import annotations` - that's not new in 3.9 but will become the default behaviour in 3.10!

I don't think we actually need any new logic to handle this, but we should really add some py39-only tests to make sure it keeps working :grin:
