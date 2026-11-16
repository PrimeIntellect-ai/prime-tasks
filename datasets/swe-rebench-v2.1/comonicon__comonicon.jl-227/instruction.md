[BUG] Option ordering is messed up because of converting Docstring to a Dictionary
**Describe the bug**
For functions that more than one option, the ordering of the documentation is random. Supposedly, that happens because the data in `CASTED_COMMANDS` is stored as a Dictionary, which does not preserve the doc order.

**Version of the package:**
1.0.0

**To Reproduce**
1. Create a module with the following code:

```julia
module M1

using Comonicon

"""
Run cell segmentation

# Options

- `-x`: Name of x column. Overrides the config value.
- `-y`: Name of y column. Overrides the config value.
- `-z`: Name of z column. Overrides the config value.
- `-g`: Name of gene column. Overrides the config value.
"""
@main function main(;x::String, y::String, z::String, g::String)
    print("Hello, world")
end

end
```

2.  Run `import M1; M1.command_main()`

**Expected behavior**
The arguments should follow the order they were defined in.

**Screenshots**
Current results:
![Screenshot from 2022-11-25 22-15-17](https://user-images.githubusercontent.com/6990194/204038107-de2c7d04-986f-4d0f-8f5c-c5d104b49fed.png)

**Potential fix**
[HIDDEN]

### Additional contract requirements

- Preserve the definition order of documented command arguments, options, and flags in the corresponding command documentation and help output.
