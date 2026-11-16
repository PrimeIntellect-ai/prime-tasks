Add accessors to UnableToCompileNode exception
For a project @mstaab and I are working on it would be useful if we could fetch the name of a constant when an `Roave\BetterReflection\NodeCompiler\Exception\UnableToCompileNode` exception is thrown:

https://github.com/Roave/BetterReflection/blob/0095a8df72ff99e1b785418e97688ff259108694/src/NodeCompiler/Exception/UnableToCompileNode.php#L44-L54

Currently we use a regular expression to analyze the exception message, retrieve the name of the constant, then define the constant, and retry the operation.

Before I open a pull request, I wanted to inquire if you were open for

- adding accessors to `UnableToCompileNode`
- extracting dedicated exceptions extending `UnableToCompileNode` (for backwards compatibility) and adding accessors there

What do you think?

### Additional contract requirements

`UnableToCompileNode` provides a public `constantName()` method. It returns the unresolved constant name when the exception represents a missing constant reference, and `null` for exceptions not created for a missing constant reference.

When created by `becauseOfNotFoundConstantReference(...)`, the exception message is `Could not locate constant "<name>" while evaluating expression in <context> at line -1`, where `<name>` is the missing constant name and `<context>` is `EmptyClass` when the compiler context has a self, or `unknown context (probably a function)` otherwise.
