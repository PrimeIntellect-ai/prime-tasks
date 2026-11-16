different behavior in io.popen function
In the C implementation of the Lua interpreter, in the io.popen function the second argument can be nil:

Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio:
```
> x,y = io.popen("ls", nil)
> assert(x)
> assert(y == nil)
>
```

Gopher lua throws an exception.
gopher-lua (current master):
```
bad argument #2 to popen (string expected, got nil)
```
[affected public project](https://github.com/luarocks/luarocks/blob/bb9d7ed38a092dde2b27e2adc7b386272f2890ee/src/luarocks/fs.lua#L33)
