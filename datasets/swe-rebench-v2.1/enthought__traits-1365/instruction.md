Traits emits its own deprecation warning on TraitMap
From running test suite of TraitsUI (with `-W default` switched on), I got the following deprecation warning coming from traits itself:
```
/Users/kchoi/.edm/envs/traitsui-test-3.6-pyqt5/lib/python3.6/site-packages/traits/traits.py:330: DeprecationWarning: 'TraitMap' trait handler has been deprecated. Use Map instead.
  other.append(TraitMap(map))
```
That is here: https://github.com/enthought/traits/blob/1af120c7d68356105d66ec6458967b5660e37e3f/traits/traits.py#L330
