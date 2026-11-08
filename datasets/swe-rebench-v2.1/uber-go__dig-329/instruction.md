Multiple decoration passes within same Scope does not work
When a dependency has multiple passes of decorations being applied within the same Module, it does not work.

For example:
```
c := dig.Container()
c.Provide(func () A { ... })
c.Provide(func (a A) B {...})
c.Provide(func (b B) C { ... })

c.Decorate(func() A { ... })
c.Decorate(func(a A) B { ... })

c.Invoke(func(c C) {
   // should see decorators of A and B getting executed, but will only see decorator of B run.
})
```

Fx version of this would be:
```
fx.Module("module",
  fx.Provide(
    func() A { ... },
    func(a A) B { ... },
    func(b B) C { ... },
  ),
  fx.Decorate(
    func() A { ... },
    func(a A) B { ... },
  ),
)
```

This seems to be a regression from one of the bug fixes that were made to Dig. Will shortly follow up with a fix.
