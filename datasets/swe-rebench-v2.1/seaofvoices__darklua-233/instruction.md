rename_variables does not rename modules in typedefs
Minimal repro, expected this:

```luau
-- types
export type foo = { bar = "idk" }
return nil

-- other module
local types = require("./types")
type foo = types.foo
```

to be transformed as:

```luau
-- types
export type foo = { bar = "idk" }
return nil

-- other module
local a = require("./types")
type foo = a.foo
```

Actually transformed without renaming the typedef:


```luau
-- types
export type foo = { bar = "idk" }
return nil

-- other module
local a = require("./types")
type foo = types.foo
```

Came from https://github.com/prvdmwrong/prvdmwrong, run the build script (`lune run build-pkg`) and accept "Publish these packages to NPM and Wally?" when prompted (comment lines around 265 to not actually publish)

![Ảnh màn hình 2024-08-20 lúc 18 21 10](https://github.com/user-attachments/assets/2c84fe37-92b2-4091-a490-c4bca321905c)
