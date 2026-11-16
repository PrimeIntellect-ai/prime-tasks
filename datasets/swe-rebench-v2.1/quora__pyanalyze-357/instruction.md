Support overloaded functions
Pyanalyze currently doesn't support overloaded functions at all. It should. Some thoughts in no particular order:
- Supporting overloads for runtime code is hard because the overloads aren't stored in the module dict. The best solution I can think of is to add a `pyanalyze.extensions.overload` decorator that somehow does register the overloads at runtime. It could be an alias of `from typing import overload` under `if TYPE_CHECKING` for compatibility with other type checkers. We could add an `@overload_implementation` decorator that collects the other overloads and stores them in the function dict or something.
- But it's much easier to support them in stubs and `implementation.py`. It might require changes to typeshed-client though.
- Internally an overloaded function could be represented as a new sister class of `pyanalyze.signature.Signature`. It would hold all of the overloaded signatures in an attribute.
- [HIDDEN] But consider this example:
```
@overload
def f(x: int) -> Literal[1]: ...
@overload
def f(x: str) -> Literal[2]: ...
y: Union[int, str]
f(y)
```
I would want this to return `Literal[1, 2]`, but naively looping over the overloads would not work for that; it would require special handling for Union. Interestingly, though, TypeScript doesn't let you do this. You have to write a separate overload for the Union instead.

- Overloads could be useful internally for representing the generic mutators (`list.append` etc.), for which there are currently complicated impl functions. These overloads would require being able to dispatch on whether a value is annotated with WeakExtension.

### Additional contract requirements

- Add a public function `patch_typing_overload()` in the module `pyanalyze.extensions`. It takes no arguments, returns `None`, and replaces `typing.overload` with the custom `pyanalyze.extensions.overload` decorator.
- The public decorator `pyanalyze.extensions.overload(func)` accepts a callable and returns the result of forwarding to the real `typing.overload` decorator.
- Pyanalyze must analyze calls to overloaded functions against their declared overload signatures. A call is accepted when its arguments match an applicable signature, and its inferred return type reflects the applicable signature or signatures. In particular, when alternatives of a union argument match different overloads, the inferred return type includes the return types of those overloads.
- If no declared overload signature accepts a call's arguments, pyanalyze reports the call as invalid.
