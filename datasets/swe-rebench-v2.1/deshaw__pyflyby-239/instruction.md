bug in name detection (PyInf#7156)
```
% cat tmp.py
def foo():
    Bar.counter = 1
class Bar(object):
    counter = 0

% tidy-imports tmp.py
[PYFLYBY] undefined name 'Bar' and no known import for it
```
Internal ticket for reference: Prop#296673
