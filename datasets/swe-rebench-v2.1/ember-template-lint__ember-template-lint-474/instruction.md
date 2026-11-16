no-shadowed-elements should allow component names including a dot to start lower case
Currently this is considered a violation of `no-shadowed-elements` rule:

```
<Foo as |s|>
  <s.bar />
</Foo>
```

If local variable is a hash and therefore component is referred to be dot notation, it can't shadow elements. Therefore the hash should not be enforced to start with an uppercase char IMO.
