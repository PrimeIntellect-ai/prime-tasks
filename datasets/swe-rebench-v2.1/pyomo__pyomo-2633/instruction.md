Fixed Vars unpickle as stale
## Summary

I'm not sure if this is a bug, but it seems unexpected? Anyway, if you pickle a model that has a fixed variable (not stale), when you unpickle it, it comes back as stale.

### Steps to reproduce the issue

```
from pyomo.environ import *
import pickle

m = ConcreteModel()
m.x = Var(domain=Binary)
m.x.fix(1)

unpickle = pickle.loads(pickle.dumps(m))

m.x.pprint()
unpickle.x.pprint()
```

```
x : Size=1, Index=None
    Key  : Lower : Value : Upper : Fixed : Stale : Domain
    None :     0 :     1 :     1 :  True : False : Binary
x : Size=1, Index=None
    Key  : Lower : Value : Upper : Fixed : Stale : Domain
    None :     0 :     1 :     1 :  True :  True : Binary
```

### Error Message

It seems like these models should be identical, even up to stale-ness, right?

### Information on your system

Pyomo version: main
Python version: 3.8
Operating system: linux
How Pyomo was installed (PyPI, conda, source): source
Solver (if applicable):
