Better handling of primitive functions and operators
Currently, primitive operators (either infix operators like `+` or builtin functions such as `length`) can only appear fully applied in the AST, inside the nodes `Op1(UnaryOp, Term)` and `Op2(BinaryOp, Term, Term)`. This has the following consequences:
 1. They must be parsed as specific keywords, that can't be used as identifiers elsewhere. As the list of operators will grow bigger in tandem with the standard lib, this will be polluting the global environment. Also, naming is not consistent: you write `lists.fold f l empty` because `fold` is written in pure Nickel in the lists standard library but write directly `map f l` or `length l` because they are primitive operators. It would be nice to have them in the corresponding libraries/namespaces only.
 2. It makes the process of adding an operator clumsier: first add the corresponding token in the lexer, then add some boilerplate to interface the lexer and the parser, then write the implementation in the abstract machine (although to be fair it's not that terrible either)
 3. They can't be partially applied, as in `let mapF = map f in ...`

## Proposals
To circumvent part of the above difficulties, one can either directly change the way operators are handled in the AST, or keep it as it is now but use a specific syntax for primitive operators.

### Without changing the AST
[HIDDEN] One could even allow this syntax only when parsing the standard library, such that in normal programs the only way to access `%map%` is to use the wrapper `lists.map`.

This solves 1. and 3., but 2. is harder: because operators must still be fully applied, the parser has to be aware of the arity of the operator, making it difficult to parse uniformly an application of `%op%`. Unless we have a different syntax for unary and binary operators. This also induces some overhead, namely calling the intermediate function.

### By changing the AST
Another direction is to make primitive operators first class terms, that can be applied to via the standard application. This raises the following questions:
 [HIDDEN]

## Conclusion
Both approaches amount roughly to the same thing: wrap primitive eager operators as lazy functions to make them compatible with standard application. The first approach makes prefix operators syntactically distinct, and wrap them in libraries as standard functions. It has the advantage of not touching the AST or the abstract machine, but makes 2. a bit clumsier to solve. The second approach avoids changing the syntax by supporting this wrapping directly in the AST. It gives a bit more flexibility, incurs a bit less execution overhead, and makes 2. simpler, because prefix operators are now just usual identifiers. The price to pay is modifying the AST and the abstract machine.

### Additional contract requirements

- Primitive operator spellings must remain usable as ordinary identifiers, including variable names and binders.
- Primitive list operations must be exposed as ordinary functions in the `lists` namespace of the standard library, so that they can be applied and partially applied like any other function. In particular, the standard library must provide the fields `lists.map` and `lists.elemAt`.
- Fully applied primitive operators must retain their existing eager evaluation behavior.
