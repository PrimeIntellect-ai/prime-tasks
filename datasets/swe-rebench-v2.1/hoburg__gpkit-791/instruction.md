Unsupported operation for units
Maybe this is out of scope, but I think it would be nice if this worked:

```
In [1]: from gpkit import Variable

In [2]: x = Variable('x', 's^0.5/m^0.5')

In [3]: y = Variable('y', '(m/s)^-0.5')
---------------------------------------------------------------------------
TypeError                                 Traceback (most recent call last)
<ipython-input-3-bdcceea699ea> in <module>()
----> 1 y = Variable('y', '(m/s)^-0.5')

C:\Python27\lib\site-packages\gpkit\nomials\variables.pyc in __init__(self, *args, **descr)
     45                 descr["label"] = arg
     46
---> 47         Monomial.__init__(self, **descr)
     48         self.__class__ = Variable
     49

C:\Python27\lib\site-packages\gpkit\nomials\nomial_math.pyc in __init__(self, exps, cs, require_positive, simplify, **descr)
     50                 units = exps.units  # pylint: disable=no-member
     51             elif exps is None or isinstance(exps, Strings):
---> 52                 vk = VarKey(**descr) if exps is None else VarKey(exps, **descr)
     53                 descr = vk.descr
     54                 units = vk.units

C:\Python27\lib\site-packages\gpkit\varkey.pyc in __init__(self, name, **kwargs)
     65             if isinstance(units, Strings):
     66                 units = units.replace("-", "dimensionless")
---> 67                 self.descr["units"] = Quantity(1.0, units)
     68             elif isinstance(units, Quantity):
     69                 self.descr["units"] = units

C:\Python27\lib\site-packages\pint\quantity.pyc in __new__(cls, value, units)
     80             inst = object.__new__(cls)
     81             inst._magnitude = _to_magnitude(value, inst.force_ndarray)
---> 82             inst._units = inst._REGISTRY.parse_units(units)._units
     83         elif isinstance(units, SharedRegistryObject):
     84             if isinstance(units, _Quantity) and units.magnitude != 1:

C:\Python27\lib\site-packages\pint\unit.pyc in parse_units(self, input_string, as_delta)
   1199             :class:`ValueError` if the expression is invalid.
   1200         """
-> 1201         units = self._parse_units(input_string, as_delta)
   1202         return self.Unit(units)
   1203

C:\Python27\lib\site-packages\pint\unit.pyc in _parse_units(self, input_string, as_delta)
   1214             return UnitsContainer()
   1215
-> 1216         units = ParserHelper.from_string(input_string)
   1217         if units.scale != 1:
   1218             raise ValueError('Unit expression cannot have a scaling factor.')

C:\Python27\lib\site-packages\pint\util.pyc in from_string(cls, input_string)
    409     @classmethod
    410     def from_string(cls, input_string):
--> 411         return cls._from_string(input_string)
    412
    413     @classmethod

C:\Python27\lib\site-packages\pint\compat\lrucache.pyc in wrapper(*args, **kwds)
    127                         stats[HITS] += 1
    128                         return result
--> 129                 result = user_function(*args, **kwds)
    130                 with lock:
    131                     root, = nonlocal_root

C:\Python27\lib\site-packages\pint\util.pyc in _from_string(cls, input_string)
    443
    444         gen = tokenizer(input_string)
--> 445         ret = build_eval_tree(gen).evaluate(cls.eval_token)
    446
    447         if isinstance(ret, Number):

C:\Python27\lib\site-packages\pint\pint_eval.pyc in evaluate(self, define_op, bin_op, un_op)
     80             if op_text not in bin_op:
     81                 raise Exception('missing binary operator "%s"' % op_text)
---> 82             left = self.left.evaluate(define_op, bin_op, un_op)
     83             return bin_op[op_text](left, self.right.evaluate(define_op, bin_op, un_op))
     84         elif self.operator:

C:\Python27\lib\site-packages\pint\pint_eval.pyc in evaluate(self, define_op, bin_op, un_op)
     81                 raise Exception('missing binary operator "%s"' % op_text)
     82             left = self.left.evaluate(define_op, bin_op, un_op)
---> 83             return bin_op[op_text](left, self.right.evaluate(define_op, bin_op, un_op))
     84         elif self.operator:
     85             # unary operator

C:\Python27\lib\site-packages\pint\util.pyc in __pow__(self, other)
    519         for key in self._d:
    520             d[key] *= other
--> 521         return self.__class__(self.scale**other, d)
    522
    523     def __truediv__(self, other):

TypeError: unsupported operand type(s) for ** or pow(): 'float' and 'ParserHelper'
```
