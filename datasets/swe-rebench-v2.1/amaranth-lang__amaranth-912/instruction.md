Signal reset cannot be set to a const value
Consider this code

```
CYCLE_OVERFLOW = Const(742500, Shape(width=22))
audgen_accum = Signal(22, reset=CYCLE_OVERFLOW) # Master clock
```

Amaranth prints this error/exception from the build/generate step:

```
    audgen_accum = Signal(22, reset=CYCLE_OVERFLOW) # Master clock
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
...
TypeError: Reset value must be a constant-castable expression, not (const 22'd742500)
```

**Expected behavior:**
Consts of matching shape should be allowed as a reset value. If they are not allowed, then the error message should be changed (language "constant-castable" is unclear and sounds wrong).

I do not have an opinion on what happens if you set a signal's reset value to a const of non-matching shape.

### Additional contract requirements

Const-castable expressions of matching shape (for example, a `Cat` of constants) are also allowed as a reset value.
