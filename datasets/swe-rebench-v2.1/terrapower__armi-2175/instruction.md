Flags sometimes can't be written to a database
When certain amounts of flags are defined, they can't be written to the database. It implies that the math calculating the number of bytes is slightly off and sometimes calculates the wrong value.

For example, writing a database when this set of flags is defined:

![Image](https://github.com/user-attachments/assets/9150a245-0882-40cd-ba97-19addf2aec63)

results in this error:

![Image](https://github.com/user-attachments/assets/6fb1d228-38ca-45f3-89c0-13d1ed65def1)

### Additional contract requirements

- Module `armi.utils.flags` provides a public class method `Flag.extend(cls, fields: dict)`. `fields` maps flag names to either integer values or `auto()` placeholders. Extending a flag class adds the named flags while preserving uniqueness.
- Module `armi.utils.flags` provides a public class method `Flag.fields()` returning the mapping of flag names to their integer values, and a public class method `Flag.from_bytes(data)` that reconstructs a flag from its byte representation.
- Module `armi.reactor.composites` provides `FlagSerializer._packImpl(values, flagClass)`, which returns a packed byte representation of the given flag values for the given flag class.
- A flag set must remain writable to a database even when a flag name is defined more than once.
