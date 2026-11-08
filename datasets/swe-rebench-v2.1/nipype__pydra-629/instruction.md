Combining `requires` and `output_file_template` for a field
I am trying to combine the effects of `requires` and `output_file_template` but failed so far.

Here is my latest attempt:

```python
@attrs.define(kw_only=True)
class MyShellSpec(pydra.specs.ShellSpec):
    mandatory_arg: str = attrs.field(
        metadata={"help_string": "mandatory arg", "mandatory": True}
    )

    enable_bar: bool  = attrs.field(
        metadata={"help_string": "optional support for bar", "argstr": "-a"}
    )

    output_arg: str = attrs.field(
        metadata={
            "help_string": "output arg",
            "argstr": "-o",
            "output_file_template": "{mandatory_arg}_foo",
        }
    )

    maybe_output_arg: str = attrs.field(
        metadata={
            "help_string": "output arg if optional arg provided",
            "argstr": "-m",
            "output_file_template": "{mandatory_arg}_bar",
            "requires": {"enable_bar"},
        }
    )
```

where I would want `maybe_output_arg` to get a templated default value **only** if an optional argument is provided.
The reasoning behind it is that the underlying executable generates additional files based on whether some optional parameters have been provided.

Assuming this is not feasible,

- Is this something we would want to allow?
- If not, what's the alternative pattern to achieve the same behavior?

Cheers,
Ghis

*EDIT: Fix typo in code snippet*
