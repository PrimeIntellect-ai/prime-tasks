Add mixin support
Seems we don't support [mixins](https://heycam.github.io/webidl/#idl-interface-mixins) yet, right?

```
interface mixin Observable {
  void addEventListener(DOMString type,
                        EventListener listener,
                        boolean useCapture);
  // ...
};
```

### Additional contract requirements

- Represent an IDL includes statement (for example, `Window includes GlobalCrypto;`) in the parsed AST with `type: "includes"`, a `target` field naming the interface, and an `includes` field naming the mixin.
- A mixin definition (`interface mixin Name { ... };`, or `partial interface mixin Name { ... };` for a partial one) must appear in the parsed AST as a node with `type: "interface mixin"`, its `name`, a `partial` flag, and its `members`. It must not be represented as an ordinary `"interface"` node.
