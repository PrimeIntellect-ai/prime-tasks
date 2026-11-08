Remove simple method calls
When calling a method like this:
```lua
foo:bar()
```
The code should be reformatted to:
```lua
foo.bar(foo)
```

### Additional contract requirements

Rewrite method-call syntax only when the receiver is a simple identifier. For such calls, produce a regular field call whose first argument is the receiver, followed by the original explicit arguments. Leave calls with field, indexed, or call-expression receivers unchanged. Make this transformation available through the rule identifier `remove_method_call`.
