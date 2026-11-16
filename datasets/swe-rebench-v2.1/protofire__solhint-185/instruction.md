Rule to require leading underscores in private variables
Hi! In [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-solidity) we use leading underscores for `private` variables and functions, and `internal` functions (to both emphasize this attribute, and avoid clashing with `public` names).

Would it be possible to add a rule to enforce this sort of thing? I currently need to disable some rules, since e.g. I have `private` variables that are also `constant` (`bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7`), and the snake case rule doesn't support leading underscores.

Thanks!

### Additional contract requirements

- The rule is enabled and configured under the identifier `private-vars-leading-underscore`.
- Private and internal state variables (including `constant` ones) must start with a leading underscore; public state variables must not. The default visibility of a state variable is internal.
- Private and internal functions must start with a leading underscore; public and external functions must not. The default visibility of a function is public.
- For functions declared inside a library, internal functions must not start with a leading underscore (only private functions must).
- The rule applies only to state variables and function names; it does not apply to function parameters, return values, or local variables.
